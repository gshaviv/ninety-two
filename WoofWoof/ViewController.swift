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
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var currentGlucoseLabel: UILabel!
    @IBOutlet var batteryLevelImage: UIImageView!
    @IBOutlet var batteryLevelLabel: UILabel!
    @IBOutlet var sensorAgeLabel: UILabel!
    @IBOutlet var agoLabel: UILabel!
    @IBOutlet var trendLabel: UILabel!
    @IBOutlet var percentLowLabel: UILabel!
    @IBOutlet var aveGlucoseLabel: UILabel!
    @IBOutlet var percentInRangeLabel: UILabel!
    @IBOutlet var a1cLabel: UILabel!
    @IBOutlet var percentHighLabel: UILabel!
    @IBOutlet var pieChart: PieChart!
    @IBOutlet var timeSpanSelector: UISegmentedControl!
    @IBOutlet var iobLabel: UILabel!
    @IBOutlet var lowCountLabel: UILabel!
    private var updater: Repeater?
    private var timeSpan = [24.h, 12.h, 6.h, 4.h, 2.h, 1.h]

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
        graphView.delegate = self
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
            currentGlucoseLabel.text = "\(Int(round(current.value)))\(trendSymbol(for: trend))"
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
        if let trend = trend {
            trendLabel.text = String(format: "%@%.1lf", trend > 0 ? "+" : "", trend)
        } else {
            trendLabel.text = ""
        }
        let iob = Storage.default.insulinOnBoard(at: Date())
        if iob > 0 && UIScreen.main.bounds.width > 350.0 {
            iobLabel.text = "IOB\n\(iob.formatted(with: "%.1lf"))"
            iobLabel.isHidden = false
        } else {
            iobLabel.isHidden = true
        }
        if defaults[.lastStatisticsCalculation] == nil || Date() > defaults[.lastStatisticsCalculation]! + 3.h {
            do {
                defaults[.lastStatisticsCalculation] = Date()
                let child = try Storage.default.db.createChild()
                var lowCount = 0
                var inLow = false
                DispatchQueue.global().async {
                    if let readings = child.evaluate(GlucosePoint.read().filter(GlucosePoint.date > Date() - 30.d).orderBy(GlucosePoint.date)), !readings.isEmpty {
                        let diffs = readings.map { $0.date.timeIntervalSince1970 }.diff()
                        let withTime = zip(readings.dropLast(), diffs)
                        let withGoodTime = withTime.filter { $0.1 < 20.m }
                        let (sumG, totalT, timeBelow, timeIn, timeAbove) = withGoodTime.reduce((0.0, 0.0, 0.0, 0.0, 0.0)) { (result, arg) -> (Double, Double, Double, Double, Double) in
                            let (sum, total, below, inRange, above) = result
                            let (gp, duration) = arg
                            let x0 = sum + gp.value * duration
                            let x1 = total + duration
                            let x2 = gp.value < defaults[.minRange] ? below + duration : below
                            let x3 = gp.value >= defaults[.minRange] && gp.value < defaults[.maxRange] ? inRange + duration : inRange
                            let x4 = gp.value >= defaults[.maxRange] ? above + duration : above
                            if gp.value > defaults[.minRange] {
                                if !inLow {
                                    lowCount += 1
                                }
                                inLow = true
                            } else {
                                inLow = false
                            }
                            return (x0, x1, x2, x3, x4)
                        }
                        let aveG = sumG / totalT
                        let a1c = (aveG / 18.05 + 2.52) / 1.583
                        DispatchQueue.main.async {
                            self.lowCountLabel.text = "\(lowCount)"
                            self.percentLowLabel.text = String(format: "%.1lf%%", timeBelow / totalT * 100)
                            self.percentInRangeLabel.text = String(format: "%.1lf%%", timeIn / totalT * 100)
                            self.percentHighLabel.text = String(format: "%.1lf%%", timeAbove / totalT * 100)
                            self.aveGlucoseLabel.text = "\(Int(round(aveG)))"
                            self.a1cLabel.text = String(format: "%.1lf%%", a1c)
                            self.pieChart.slices = [PieChart.Slice(value: CGFloat(timeBelow), color: .red),
                                                    PieChart.Slice(value: CGFloat(timeIn), color: .green),
                                                    PieChart.Slice(value: CGFloat(timeAbove), color: .yellow)]
                        }
                    }
                }
            } catch {}
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

    func addRecord(meal: Record.Meal? = nil, units: Int? = nil, note: String? = nil) {
        let ctr = AddRecordViewController()
        ctr.kind = meal
        ctr.units = units
        ctr.note = note
        ctr.onSelect = { (record, prediction) in
            if record.id == nil {
                record.save(to: Storage.default.db)
                Storage.default.lastDay.entries.append(record)
            } else {
                record.save(to: Storage.default.db)
            }
            self.graphView.records = Storage.default.lastDay.entries
            let interaction = INInteraction(intent: record.intent, response: nil)
            interaction.donate { _ in }
            if let prediction = prediction {
                self.graphView.prediction = prediction
            }
            
        }
        present(ctr, animated: true, completion: nil)
    }


    @IBAction func handleMore(_ sender: Any) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Add to Diary", style: .default, handler: { (_) in
            self.addRecord()
        }))

        sheet.addAction(UIAlertAction(title: "Calibrate", style: .default, handler: { (_) in
            self.calibrate()
        }))

        sheet.addAction(UIAlertAction(title: "Reconnect", style: .default, handler: { (_) in
            defaults[.nextNoSensorAlert] = Date()
            Central.manager.restart()
        }))

        let group = DispatchGroup()
        group.enter()
        var has = false
        INVoiceShortcutCenter.shared.getAllVoiceShortcuts { (results, _) in
            for voiceShortcut in results ?? [] {
                if voiceShortcut.shortcut.intent is CheckGlucoseIntent {
                    has = true
                    break
                }
            }
            group.leave()
        }
        group.wait()

        if !has {
            sheet.addAction(UIAlertAction(title: "Add to Siri", style: .default, handler: { (_) in
                let intent = CheckGlucoseIntent()
                intent.suggestedInvocationPhrase = "What's my glucose"
                if let shortcut = INShortcut(intent: intent) {
                    let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
                    viewController.delegate = self
                    self.present(viewController, animated: true)
                }
            }))
        }

        sheet.addAction(UIAlertAction(title: "History", style: .default, handler: { (_) in
            let hvc = self.storyboard?.instantiateViewController(withIdentifier: "history") as? HistoryViewController
            _ = hvc?.view
            hvc?.percentLowLabel.text = self.percentLowLabel.text
            hvc?.aveGlucoseLabel.text = self.aveGlucoseLabel.text
            hvc?.percentInRangeLabel.text = self.percentInRangeLabel.text
            hvc?.a1cLabel.text = self.a1cLabel.text
            hvc?.percentHighLabel.text = self.percentHighLabel.text
            hvc?.pieChart.slices = self.pieChart.slices
            self.show(hvc!, sender: nil)
        }))

        sheet.addAction(UIAlertAction(title: "Report", style: .default, handler: { (_) in
            self.selectReportPeriod()
            }))

        sheet.addAction(UIAlertAction(title: "Settings", style: .default, handler: { (_) in
            self.showSettings()
        }))

        sheet.addAction(UIAlertAction(title: "Backup", style: .default, handler: { (_) in
            Storage.default.db.async {
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
        }))

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(sheet, animated: true, completion: nil)
    }

    private func showSettings() {
        let ctr = UIStoryboard(name: "Settings", bundle: nil).instantiateInitialViewController() as! SettingsViewController

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
            ctr.addGroup("Watch")
            ctr.addTime(title: "Complication wakeup time", get: {
                (defaults[.watchWakeupTime] / 60, defaults[.watchWakeupTime] % 60)
            }) {
                defaults[.watchWakeupTime] = $0 * 60 + $1
            }
            ctr.addTime(title: "Complication sleep time", get: {
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
        show(ctr, sender: nil)
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

    func didUpdate(addedHistory: [GlucosePoint]) {
        if UIApplication.shared.applicationState != .background {
            update()
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
        let ctr = AddRecordViewController()
        ctr.editRecord = record
        ctr.onSelect = { (_,_) in
            self.graphView.prediction = nil
            self.graphView.records = Storage.default.lastDay.entries
        }
        ctr.onCancel = {
            self.graphView.prediction = nil
            self.graphView.records = Storage.default.lastDay.entries
        }
        present(ctr, animated: true, completion: nil)
    }

    func didTouch(record: Record) {
        guard record.isMeal else {
            return
        }

        DispatchQueue.global().async {
            let readings = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date < record.date).orderBy(GlucosePoint.date)) ?? []
            guard let current = readings.last else {
                return
            }
            let meals = Storage.default.allMeals.filter { $0.date < record.date  }
            let relevantMeals = Storage.default.relevantMeals(to: record)
            var points = [[GlucosePoint]]()
            guard !relevantMeals.isEmpty else {
                return
            }
            for meal in relevantMeals {
                let nextEvent = meals.first(where: { $0.date > meal.date })
                let nextDate = nextEvent?.date ?? Date.distantFuture
                let relevantPoints = readings.filter { $0.date >= meal.date && $0.date <= nextDate && $0.date < meal.date + 5.h }
                points.append(relevantPoints)
            }
            var highs: [Double] = []
            var lows: [Double] = []
            var timeToHigh: [TimeInterval] = []
            for (meal, mealPoints) in zip(relevantMeals, points) {
                guard mealPoints.count > 2 else {
                    continue
                }
                let stat = mealStatistics(meal: meal, points: mealPoints)
                highs.append(stat.0)
                lows.append(stat.2)
                timeToHigh.append(stat.1)
            }
            let predictedHigh = CGFloat(round(highs.sorted().median() + current.value))
            let predictedHigh25 = CGFloat(round(highs.sorted().percentile(0.2) + current.value))
            let predictedHigh75 = CGFloat(round(highs.sorted().percentile(0.8) + current.value))
            let predictedLow = CGFloat(round(lows.sorted().percentile(0.1) + current.value))
            let predictedTime = record.date + timeToHigh.sorted().median()
            DispatchQueue.main.async {
                self.graphView.prediction = Prediction(mealTime: record.date, highDate: predictedTime, h25: predictedHigh25, h50: predictedHigh, h75: predictedHigh75, low: predictedLow)
            }
        }
    }
}
