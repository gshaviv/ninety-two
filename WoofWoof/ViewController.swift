//
//  ViewController.swift
//  WoofWoof
//
//  Created by Guy on 14/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import UIKit
import Sqlable
import WoofKit
import Intents
import IntentsUI
import PDFCreation
import PDFKit
import WatchConnectivity
import UserNotifications
import Zip

class ViewController: UIViewController {
    @IBOutlet var connectingLabel: UILabel!
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var currentGlucoseLabel: UILabel!
    @IBOutlet var batteryLevelImage: UIImageView!
    @IBOutlet var batteryLevelLabel: UILabel!
    @IBOutlet var sensorAgeLabel: UILabel!
    @IBOutlet var agoLabel: UILabel!
    @IBOutlet var trendLabel: UILabel!
    var summaryController: SummaryViewController?
    @IBOutlet var timeSpanSelector: UISegmentedControl!
    @IBOutlet var iobLabel: UILabel!
    private var updater: Repeater?
    private var timeSpan = [24.h, 12.h, 6.h, 4.h, 2.h, 1.h]

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.destination {
        case let c as SummaryViewController:
            summaryController = c

        case let nav as UINavigationController:
            switch nav.viewControllers[0] {
            case let c as RecordViewController:
                if let r = sender as? Record {
                    c.editRecord = r
                    c.onSelect = { (_,prediction) in
                        self.graphView.prediction = prediction
                        self.graphView.records = Storage.default.lastDay.entries
                    }
                    c.onCancel = {
                        self.graphView.prediction = nil
                        self.graphView.records = Storage.default.lastDay.entries
                    }
                } else {
                    c.onSelect = { (record, prediction) in
                        if !Storage.default.allEntries.map({ $0.id }).contains(record.id) {
                            Storage.default.reloadToday()
                            if defaults[.writeHealthKit] && record.bolus > 0 {
                                HealthKitManager.shared?.write(records: [record])
                            }
                        }
                        self.graphView.records = Storage.default.lastDay.entries
                        let interaction = INInteraction(intent: record.intent, response: nil)
                        interaction.donate { _ in }
                        if let prediction = prediction {
                            self.graphView.prediction = prediction
                        }
                    }
                }

            default:
                break
            }

        default:
            break
        }
    }

    private func batteryLevelIcon(for level: Int) -> UIImage {
        switch level {
        case 90...:
            return UIImage(named: "battery-5")!

        case 60..<90:
            return UIImage(named: "battery-4")!

        case 30..<60:
            return UIImage(named: "battery-3")!

        case 20..<30:
            return UIImage(named: "battery-2")!

        default:
            return UIImage(named: "battery-1")!
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        update()
        MiaoMiao.addDelegate(self)
        timeSpanSelector.selectedSegmentIndex = defaults[.timeSpanIndex]
        graphView.xTimeSpan = timeSpan[defaults[.timeSpanIndex]]
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        agoLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .medium)

        graphView.records = Storage.default.lastDay.entries
        graphView.manual = Storage.default.lastDay.manualMeasurements
        graphView.delegate = self
        Central.manager.onStateChange { (_, state) in
            DispatchQueue.main.async {
                switch state {
                case .unknown, .bluetoothOn:
                    self.connectingLabel.text = "Searching for MiaoMiao..."
                    self.connectingLabel.isHidden = false

                case .unavailable:
                    self.connectingLabel.text = "Bluetooth Unavailable"
                    self.connectingLabel.isHidden = false

                case .bluetoothOff:
                    self.connectingLabel.text = "Bluetooth is off"
                    self.connectingLabel.isHidden = false

                case .found:
                    self.connectingLabel.text = "Connecting to MiaoMiao..."
                    self.connectingLabel.isHidden = false

                case .error:
                    self.connectingLabel.text = "Bluetooth error"
                    self.connectingLabel.isHidden = false

                case .ready:
                    self.connectingLabel.text = "MiaoMiao connected"
                }
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(deletedPoints), name: DeletedPointsNotification, object: nil)
    }

    @IBAction func selectedTimeSpan(_ sender: UISegmentedControl) {
        defaults[.timeSpanIndex] = sender.selectedSegmentIndex
        graphView.xTimeSpan = timeSpan[sender.selectedSegmentIndex]
    }


    func update() {
        if let lastH = MiaoMiao.allReadings.last?.date {
            let last = max(lastH, MiaoMiao.trend?.last?.date ?? lastH)
            let end = Date().timeIntervalSince(last) < 12.h ? Date() : last

            graphView.points = MiaoMiao.allReadings
            graphView.yRange.max = max(graphView.yRange.max, 140)
            graphView.yRange.min = min(graphView.yRange.min, 70)
            if !MiaoMiao.allReadings.isEmpty {
                graphView.xRange.max = end
                graphView.xRange.min = graphView.xRange.max - 24.h
            }
        } else {
            logError("no last?")
        }
        let trend = trendValue()
        if let current = MiaoMiao.currentGlucose {
            let levelStr = current.value > 70 ? current.value.formatted(with: "%.0lf") : current.value.formatted(with: "%.1lf")
            currentGlucoseLabel.text = "\(levelStr)\(trendSymbol(for: trend))"
            updateTimeAgo()
        } else {
            currentGlucoseLabel.text = "--"
            UIApplication.shared.applicationIconBadgeNumber = 0
            agoLabel.text = ""
        }
        batteryLevelImage.image = batteryLevelIcon(for: MiaoMiao.batteryLevel)
        batteryLevelLabel.text = "\(MiaoMiao.batteryLevel)%"

        updater = Repeater.every(1, queue: DispatchQueue.main) { (_) in
            self.updateTimeAgo()
        }
        if let time = MiaoMiao.sensorAge {
            let age = Int(time / 1.m)
            sensorAgeLabel.text = "\(age / 24 / 60)d:\(age / 60 % 24)h"
        } else {
            sensorAgeLabel.text = "?"
        }
        switch MiaoMiao.sensorState {
        case .expired:
            sensorAgeLabel.textColor = .red
        default:
            sensorAgeLabel.textColor = .black
        }
        if let trend = trend {
            trendLabel.text = String(format: "%@%.1lf", trend > 0 ? "+" : "", trend)
        } else {
            trendLabel.text = ""
        }
        let iob = Storage.default.insulinOnBoard(at: Date())
        if iob > 0 && UIScreen.main.bounds.width > 350.0 {
            iobLabel.text = "BOB\n\(iob.formatted(with: "%.1lf"))"
            iobLabel.isHidden = false
        } else {
            iobLabel.isHidden = true
        }
        if defaults[.lastStatisticsCalculation] == nil || Date() > defaults[.lastStatisticsCalculation]! + min(max(3.h, defaults.summaryPeriod.d / 50), 6.h) {
            summaryController?.updateSummary()
        }
    }

    private func updateTimeAgo() {
        if let current = MiaoMiao.currentGlucose {
            let time = Int(round(Date().timeIntervalSince(current.date)))
            agoLabel.text = String(format: "%ld:%02ld", time / 60, time % 60)
        } else {
            agoLabel.text = ""
        }
    }

    func addRecord(meal: Record.MealType? = nil, units: Int? = nil, note: String? = nil) {
        self.performSegue(withIdentifier: "addRecord", sender: nil)
    }

    func addManualMeasurement() {
        let alert = UIAlertController(title: "Manual Measurement", message: "Blood Glucose", preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add", style: .default, handler: { (_) in
            guard let tf = alert.textFields?[0].text, let v = Double(tf) else {
                return
            }
            Storage.default.db.async {
                let m = ManualMeasurement(date: Date(), value: v)
                Storage.default.db.evaluate(m.insert())
                DispatchQueue.main.async {
                    Storage.default.reloadToday()
                    self.graphView.manual = Storage.default.lastDay.manualMeasurements
                }
            }
        }))
        present(alert, animated: true, completion: nil)
    }


    @IBAction func handleMore(_ sender: Any) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Add to Diary", style: .default, handler: { (_) in
            self.performSegue(withIdentifier: "addRecord", sender: nil)
        }))

        sheet.addAction(UIAlertAction(title: "Add Manual Measurement", style: .default, handler: { (_) in
            self.addManualMeasurement()
        }))

        sheet.addAction(UIAlertAction(title: "Calibrate", style: .default, handler: { (_) in
            self.calibrate()
        }))

        sheet.addAction(UIAlertAction(title: "Reconnect MiaoMiao", style: .default, handler: { (_) in
            Central.manager.restart()
        }))

        sheet.addAction(UIAlertAction(title: "History", style: .default, handler: { (_) in
            self.performSegue(withIdentifier: "history", sender: nil)
        }))

        sheet.addAction(UIAlertAction(title: "Report", style: .default, handler: { (_) in
            self.selectReportPeriod()
            }))

        sheet.addAction(UIAlertAction(title: "Settings", style: .default, handler: { (_) in
            self.showSettings()
        }))

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(sheet, animated: true, completion: nil)
    }

    private func showSettings() {
        let ctr = UIStoryboard(name: "Settings", bundle: nil).instantiateInitialViewController() as! SettingsViewController

        ctr.addGroup("General")
        if HealthKitManager.isAvailable {
            ctr.addBool(title: "Store data in HealthKit", get: { () -> Bool in
                return defaults[.writeHealthKit]
            }) {
                guard HealthKitManager.isAvailable else {
                    logError("HealthKit not available")
                    return
                }
                defaults[.writeHealthKit] = $0
                if $0 {
                    HealthKitManager.authorize({ (granted) in
                        guard granted else {
                            logError("HK permission not granted")
                            return
                        }
                        HealthKitManager.shared?.findLast {
                            let date = $0 ?? Date.distantPast
                            guard let points = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > date).orderBy(GlucosePoint.date))  else {
                                return
                            }
                            log("last HK record \(date), writng \(points.count) points")
                            HealthKitManager.shared?.write(points: points)

                            let boluses = Storage.default.db.evaluate(Record.read().filter(Record.date > date && Record.bolus > 0).orderBy(Record.date)) ?? []
                            if !boluses.isEmpty {
                                HealthKitManager.shared?.write(records: boluses)
                            }
                        }
                    })
                }
            }
        }
        ctr.addEnum("Summary Timeframe", count: UserDefaults.summaryPeriods.count, get: { () -> Int in
            return defaults[.summaryPeriod]
        }, set: {
            defaults[.summaryPeriod] = $0
        }) {
            $0 == 0 ? "24 hours" : "\(UserDefaults.summaryPeriods[$0]) days"
        }

        ctr.addGroup("Target Range")
        ctr.addValue(title: "Max", get: {
            String(format: "%lg", defaults[.maxRange])
        }) {
            defaults[.maxRange] = $0
        }
        ctr.addValue(title: "Min", get: {
            String(format: "%lg", defaults[.minRange])
        }) {
            defaults[.minRange] = $0
        }

        ctr.addGroup("Alerts")
        ctr.addValue(title: "High Level", get: {
            String(format: "%lg", defaults[.highAlertLevel])
        }) {
            defaults[.highAlertLevel] = $0
        }
        ctr.addValue(title: "Low Level", get: {
            String(format: "%lg", defaults[.lowAlertLevel])
        }) {
            defaults[.lowAlertLevel] = $0
        }
        ctr.addBool(title: "Vibrate", get: { () -> Bool in
            return defaults[.alertVibrate]
        }) {
            defaults[.alertVibrate] = $0
        }

        ctr.addGroup("Insulin (Bolus) Profile")
        ctr.addValue(title: "DIA (m)", get: { () -> String in
            return defaults[.diaMinutes].formatted(with: "%.0lf")
        }) {
            if $0 >= 2 * defaults[.peakMinutes] {
            defaults[.diaMinutes] = $0
            }
        }
        ctr.addValue(title: "Peak (m)", get: { () -> String in
            return defaults[.peakMinutes].formatted(with: "%.0lf")
        }) {
            if $0 < defaults[.diaMinutes] / 2 {
            defaults[.peakMinutes] = $0
            }
        }
        ctr.addValue(title: "Delay (m)", get: { () -> String in
            return defaults[.delayMinutes].formatted(with: "%.0lf")
        }) {
            defaults[.delayMinutes] = $0
        }
        if WCSession.default.isPaired && WCSession.default.isWatchAppInstalled {
            ctr.addGroup("Watch Complication Updates")
            ctr.addTime(title: "Wakeup time", get: {
                (defaults[.watchWakeupTime] / 60, defaults[.watchWakeupTime] % 60)
            }) {
                defaults[.watchWakeupTime] = $0 * 60 + $1
            }
            ctr.addTime(title: "Sleep time", get: {
                (defaults[.watchSleepTime] / 60, defaults[.watchSleepTime] % 60)
            }) {
                defaults[.watchSleepTime] = $0 * 60 + $1
            }
        }

        ctr.addGroup("Colors")
        ctr.addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color5]
        }) {
            defaults[.color5] = $0
        }
        ctr.addValue(title: "Value", get: { () -> String in
            defaults[.level4].formatted(with: "%lg")
        }) {
            defaults[.level4] = $0
        }
        ctr.addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color4]
        }) {
            defaults[.color4] = $0
        }
        ctr.addValue(title: "Value", get: { () -> String in
            defaults[.level3].formatted(with: "%lg")
        }) {
            defaults[.level3] = $0
        }
        ctr.addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color3]
        }) {
            defaults[.color3] = $0
        }
        ctr.addValue(title: "Value", get: { () -> String in
            defaults[.level2].formatted(with: "%lg")
        }) {
            defaults[.level2] = $0
        }
        ctr.addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color2]
        }) {
            defaults[.color2] = $0
        }
        ctr.addValue(title: "Value", get: { () -> String in
            defaults[.level1].formatted(with: "%lg")
        }) {
            defaults[.level1] = $0
        }
        ctr.addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color1]
        }) {
            defaults[.color1] = $0
        }
        ctr.addValue(title: "Value", get: { () -> String in
            defaults[.level0].formatted(with: "%lg")
        }) {
            defaults[.level0] = $0
        }
        ctr.addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color0]
        }) {
            defaults[.color0] = $0
        }

        ctr.addGroup("Report")
        ctr.addBool(title: "Daily Pattern", get: { () -> Bool in
            return defaults[.includePatternReport]
        }) {
            defaults[.includePatternReport] = $0
        }
        ctr.addBool(title: "Meal Pattern", get: { () -> Bool in
            return defaults[.includeMealReport]
        }) {
            defaults[.includeMealReport] = $0
        }
        ctr.addBool(title: "Daily Logs", get: { () -> Bool in
            return defaults[.includeDailyReport]
        }) {
            defaults[.includeDailyReport] = $0
        }

        var siriActions = Set<Record>()
        let group = DispatchGroup()
        group.enter()
        var has = false
        INVoiceShortcutCenter.shared.getAllVoiceShortcuts { (results, _) in
            for voiceShortcut in results ?? [] {
                if let i = voiceShortcut.shortcut.intent as? DiaryIntent {
                    siriActions.insert(i.record)
                } else if voiceShortcut.shortcut.intent is CheckGlucoseIntent {
                    has = true
                }
            }
            group.leave()
        }
        group.wait()

        var entries = [Record: Int]()
        if !siriActions.contains(Record(date: Date.distantFuture, meal: Record.MealType.breakfast)) {
            entries[Record(date: Date.distantFuture, meal: Record.MealType.breakfast)] = 400
        }
        if !siriActions.contains(Record(date: Date.distantFuture, meal: Record.MealType.lunch)) {
            entries[Record(date: Date.distantFuture, meal: Record.MealType.lunch)] = 300
        }
        if !siriActions.contains(Record(date: Date.distantFuture, meal: Record.MealType.dinner)) {
            entries[Record(date: Date.distantFuture, meal: Record.MealType.dinner)] = 200
        }
        if !siriActions.contains(Record(date: Date.distantFuture, meal: Record.MealType.other)) {
            entries[Record(date: Date.distantFuture, meal: Record.MealType.other)] = 100
        }
        Storage.default.allEntries.filter { $0.date > Date() - 1.y }.map { Record(date: Date.distantFuture, meal: $0.type, bolus: $0.bolus, note: $0.note) }.forEach {
            if !siriActions.contains($0) {
                if let count = entries[$0] {
                    entries[$0] = count + 1
                } else {
                    entries[$0] = 1
                }
            }
            if let note = $0.note {
                let r = Record(date: Date.distantFuture, meal: nil, bolus: $0.bolus, note: note)
                if !siriActions.contains(r) {
                    if let count = entries[r] {
                        entries[r] = count + 1
                    } else {
                        entries[r] = 1
                    }
                }
            }
        }
        for key in entries.keys {
            if key.type != nil, let note = key.note {
                let r = Record(date: Date.distantFuture, meal: nil, bolus: key.bolus, note: note)
                if let full = entries[key], let partial = entries[r], partial == full {
                    entries[r] = nil
                } else if siriActions.contains(key) {
                    entries[r] = nil
                }
            }
        }
        let common = entries.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }.filter { $0.1 > 6 }
        if !common.isEmpty || !has {
            let top = common[0 ..< min(common.count, 8)].map { $0.0 }
            ctr.addGroup("Add Siri Shortcut")
            if !has {
                ctr.addRow(title: "Glucose Measurment", subtitle: "What's my glucose?", configure: {
                    $0.imageView?.image = UIImage(named: "AppIcon")
                    $0.accessoryView = UIImageView(image: UIImage(named: "plus"))
                }) {
                    let intent = CheckGlucoseIntent()
                    intent.suggestedInvocationPhrase = "What's my glucose"
                    if let shortcut = INShortcut(intent: intent) {
                        let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
                        viewController.delegate = self
                        self.present(viewController, animated: true)
                    }
                }
            }
            for record in top {
                ctr.addRow(title: record.intent.value(forKey: "title") as? String ?? record.intent.suggestedInvocationPhrase ?? "", subtitle: record.intent.value(forKey: "subtitle") as? String, configure: {
                    $0.imageView?.image = UIImage(named: "AppIcon")
                    $0.accessoryView = UIImageView(image: UIImage(named: "plus"))
                }) {
                    if let shortcut = INShortcut(intent: record.intent) {
                        let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
                        viewController.delegate = self
                        self.present(viewController, animated: true)
                    }
                }
            }
        }

        ctr.addGroup("")
        ctr.addButton("Backup Database") {
            Storage.default.db.async {
                try? Storage.default.db.execute("vacuum")
                let documentsDirectory = FileManager.default.urls(for:.documentDirectory, in: .userDomainMask)[0]
                let zipFilePath = documentsDirectory.appendingPathComponent("archive.zip")
                let path = Storage.default.dbUrl.path
                let shm = URL(fileURLWithPath: "\(path)-shm")
                let wal = URL(fileURLWithPath: "\(path)-wal")
                try? Zip.zipFiles(paths: [Storage.default.dbUrl, shm, wal], zipFilePath: zipFilePath, password: nil, progress: nil)
                DispatchQueue.main.async {
                    let activityController = UIActivityViewController(activityItems: [zipFilePath], applicationActivities: nil)
                    activityController.excludedActivityTypes = [.postToTwitter, .postToFacebook, .message, .postToWeibo, .print, .copyToPasteboard, .assignToContact]
                    activityController.completionWithItemsHandler = { _,_,_,_ in
                        try? FileManager.default.removeItem(at: zipFilePath)
                    }
                    self.present(activityController, animated: true, completion: nil)
                }
            }
        }
        if let old = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date < Date() - 1.y).limit(1)), !old.isEmpty {
            ctr.addButton("Delete records older than 1y") {
                do {
                    let timestamp = Int((Date() - 1.y).timeIntervalSince1970)
                    try Storage.default.db.execute("delete from \(GlucosePoint.tableName) where date < \(timestamp)")
                    try Storage.default.db.execute("delete from \(Calibration.tableName) where date < \(timestamp)")
                    try Storage.default.db.execute("delete from \(Record.tableName) where date < \(timestamp)")
                    try Storage.default.db.execute("delete from \(ManualMeasurement.tableName) where date < \(timestamp)")
                    try Storage.default.db.execute("vacuum")
                    let alert = UIAlertController(title: "Done", message: "Deleted records over 1 year old", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                } catch {}
            }
        }
        show(ctr, sender: nil)
    }

    @objc private func deletedPoints() {
        MiaoMiao.historyChanged()
        Storage.default.reloadToday()
    }

    private func selectReportPeriod() {
        let ctr = DateRangePickerController()
        ctr.onSelect = {
            if $0 == 0 {
                let ctr2 = DateFromToPickerController()
                ctr2.onSelect = {
                    self.makeReport(from: $0, to: $1)
                }
                self.present(ctr2, animated: true, completion: nil)
            } else {
                self.makeReport(from: Date() - $0, to: Date())
            }
        }
        self.present(ctr, animated: true, completion: nil)
    }

    private func makeReport(from: Date, to: Date) {
        do {
            let report = try GlucoseReport(from: from.startOfDay, to: to.endOfDay, database: Storage.default.db)
            DispatchQueue.global().async {
                do {
                    let pdf = try report.create()
                    DispatchQueue.main.async {
                        let ctr = PDFViewerViewController.controller(for: pdf)
                        self.present(ctr, animated: true, completion: nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: "Error", message: "Error encountered while generating report", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                    }
                }
            }
        } catch {

        }
    }
    
    @IBAction func calibrate() {
        MiaoMiao.Command.startReading()
        let alert = UIAlertController(title: "Calibrate", message: "Enter BG measurement", preferredStyle: .alert)
        alert.addTextField {
            $0.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add", style: .default, handler: { (_) in
            if let text = alert.textFields![0].text, let bg = Double(text), let current = MiaoMiao.currentGlucose {
                do {
                    let c = Calibration(date: Date(), value: bg)
                    try Storage.default.db.perform(c.insert())
                    let factor = bg / current.value
                    defaults[.additionalSlope] *= factor
                    if abs(factor - 1) > 0.1 {
                        if let age = MiaoMiao.sensorAge, age < 1.d {
                            defaults[.nextCalibration] = Date() + 6.h
                        } else if defaults[.nextCalibration] == nil {
                            defaults[.nextCalibration] = Date() + 3.h
                        }
                    }
                    self.currentGlucoseLabel.text = "\(Int(round(bg)))\(self.trendSymbol(for: self.trendValue()))"
                    UIApplication.shared.applicationIconBadgeNumber = Int(round(bg))
                    MiaoMiao.last24hReadings.append(c)
                    defaults[.sensorSerial] = MiaoMiao.serial
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationIdentifier.calibrate])
                } catch _ {}
            }
        }))
        present(alert, animated: true, completion: nil)
    }

    @objc private func didEnterForeground() {
        update()
    }

    @objc private func didEnterBackground() {
        updater = nil
        graphView.points = []
        graphView.records = []
    }

    private func trendValue() -> Double? {
        return UIApplication.theDelegate.trendCalculator.value
    }

    private func trendSymbol(for trend: Double?) -> String {
        return UIApplication.theDelegate.trendSymbol(for: trend)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let intent = CheckGlucoseIntent()
        intent.suggestedInvocationPhrase = "What's my glucose"
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            // Handle error
        }
    }

    @IBAction func showPercentage(_ sender: Any) {
        batteryLevelImage.isHidden = true
        batteryLevelLabel.isHidden = false
        DispatchQueue.main.after(withDelay: 3) {
            self.batteryLevelImage.isHidden = false
            self.batteryLevelLabel.isHidden = true
        }
    }
    
}

extension ViewController: MiaoMiaoDelegate {
    func miaomiaoError(_ error: String) {
        self.connectingLabel.text = error
        self.connectingLabel.isHidden = false
    }

    func didUpdate(addedHistory: [GlucosePoint]) {
        if UIApplication.shared.applicationState != .background {
            if !connectingLabel.isHidden {
                UIView.animate(withDuration: 0.25, animations: {
                    self.connectingLabel.alpha = 0
                }, completion: { (_) in
                    self.connectingLabel.alpha = 1
                    self.connectingLabel.isHidden = true
                })
            }
            update()
        } else {
            if !connectingLabel.isHidden {
                connectingLabel.isHidden = true
            }
        }
    }
}

extension ViewController: INUIAddVoiceShortcutViewControllerDelegate {
    func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?) {
        if let voiceShortcut = voiceShortcut {
            log("Added \(voiceShortcut)")
        }
        controller.dismiss(animated: true, completion: nil)
    }

    func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
}


extension ViewController: GlucoseGraphDelegate {
    func didDoubleTap(record: Record) {
        self.performSegue(withIdentifier: "addRecord", sender: record)
    }

    func didTouch(record: Record) {
        guard record.isMeal else {
            return
        }

        DispatchQueue.global().async {
            let prediction = Storage.default.prediction(for: record) ?? Storage.default.calculatedLevel(for: record)
            DispatchQueue.main.async {
                self.graphView.prediction = prediction
            }
        }
    }
}
