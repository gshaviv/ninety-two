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
    private var lastTouchedRecord: Record?
    @IBOutlet var connectingLabel: UILabel!
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var currentGlucoseLabel: UILabel!
    @IBOutlet var batteryLevelImage: UIImageView!
    @IBOutlet var batteryLevelLabel: UILabel!
    @IBOutlet var sensorAgeLabel: UILabel!
    @IBOutlet var agoLabel: UILabel!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet var trendLabel: UILabel!
    var summaryController: SummaryViewController?
    @IBOutlet var timeSpanSelector: UISegmentedControl!
    @IBOutlet var iobLabel: UILabel!
    private var updater: Repeater?
    private var timeSpan = [24.h, 12.h, 6.h, 4.h, 2.h, 1.h]
    @IBOutlet weak var insulinActionLabel: UILabel!
    
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
                
            case let c as SummaryViewController:
                summaryController = c


            default:
                break
            }

        default:
            break
        }
    }

    @IBAction func ShowInsulatinAction(_ sender: Any) {
        insulinActionLabel.isHidden = false
        insulinActionLabel.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.insulinActionLabel.alpha = 1
            self.iobLabel.alpha = 0
        }
        UIView.animate(withDuration: 0.3, delay: 2, options: .curveLinear, animations: {
            self.insulinActionLabel.alpha = 0
            self.iobLabel.alpha = 1
        }, completion: { _ in
            self.insulinActionLabel.isHidden = true
        })
    }
    
    private func batteryLevelIcon(for level: Int) -> UIImage {
        switch level {
        case 95...:
            return UIImage(named: "battery-5")!

        case 65..<95:
            return UIImage(named: "battery-4")!

        case 35..<65:
            return UIImage(named: "battery-3")!

        case 10..<35:
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
        NotificationCenter.default.addObserver(self, selector: #selector(willDeletePoints), name: WillDeletePointsNotification, object: nil)
    }

    @IBAction func selectedTimeSpan(_ sender: UISegmentedControl) {
        defaults[.timeSpanIndex] = sender.selectedSegmentIndex
        graphView.xTimeSpan = timeSpan[sender.selectedSegmentIndex]
    }
    
    @objc private func willDeletePoints() {
        MiaoMiao.flushToDatabase()
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
        if let trend = trendValue(), let current = MiaoMiao.currentGlucose {
            let levelStr = current.value > 70 ? current.value % ".0lf" : current.value % ".1lf"
            currentGlucoseLabel.text = "\(levelStr)\(trendSymbol(for: trend))"
            updateTimeAgo()
        } else {
            currentGlucoseLabel.text = "--"
            UIApplication.shared.applicationIconBadgeNumber = 0
            agoLabel.text = ""
        }
        batteryLevelImage.image = batteryLevelIcon(for: MiaoMiao.batteryLevel)
        switch MiaoMiao.batteryLevel {
        case 80...:
            batteryLevelImage.tintColor = .label

        case 25 ..< 80:
            batteryLevelImage.tintColor = .secondaryLabel
            
        default:
            batteryLevelImage.tintColor = .tertiaryLabel
        }
        batteryLevelLabel.text = "\(MiaoMiao.batteryLevel)%"

        updater = Repeater.every(1, queue: DispatchQueue.main) { (_) in
            self.updateTimeAgo()
        }
        if let time = MiaoMiao.sensorAge {
            let age = Int(time / 1.m)
            sensorAgeLabel.text = "\(age / 24 / 60)d:\(age / 60 % 24)h"
            switch Int(rint(time / 1.d)) {
            case defaults[.libreDays]...:
                sensorAgeLabel.textColor = .systemRed
                
            case (defaults[.libreDays] - 1) ..< defaults[.libreDays]:
                sensorAgeLabel.textColor = .systemYellow
                
            default:
                sensorAgeLabel.textColor = .label
            }
        } else {
            sensorAgeLabel.text = "?"
            sensorAgeLabel.textColor = .secondaryLabel
        }
        
        switch MiaoMiao.sensorState {
        case .expired:
            sensorAgeLabel.textColor = .systemRed
        default:
            sensorAgeLabel.textColor = .secondaryLabel
        }
        if let trend = trendValue() {
            trendLabel.text = String(format: "%@%.1lf", trend > 0 ? "+" : "", trend)
        } else {
            trendLabel.text = ""
        }
        let iob = Storage.default.insulinOnBoard(at: Date())
        if iob > 0 && UIScreen.main.bounds.width > 350.0 {
            let action = Storage.default.insulinAction(at: Date())
            iobLabel.text = "BOB\n\(iob % ".1lf")"
            iobLabel.isHidden = false
            insulinActionLabel.text = "\(action % ".2lf")"
        } else {
            iobLabel.isHidden = true
        }
        summaryController?.updateSummary()
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
            if let text = alert.textFields![0].text, let bg = Double(text), bg > 65 && bg < 185, let trend = self.trendValue() {
                MiaoMiao.addCalibration(value: bg)
                self.currentGlucoseLabel.text = "\(Int(round(bg)))\(trendSymbol(for: trend))"
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
        var showBasedOnMeals = true
        if let last = lastTouchedRecord, last.id == record.id {
            showBasedOnMeals = false
        }
        DispatchQueue.global().async {
            let prediction: Prediction?
            let basedOnMeals = Storage.default.prediction(for: record)
            prediction =  showBasedOnMeals ? basedOnMeals ?? Storage.default.calculatedLevel(for: record) : Storage.default.calculatedLevel(for: record)
            DispatchQueue.main.async {
                self.graphView.prediction = prediction
            }
//            if ParamsPerTimeOfDay.params(for: record.date) == nil && (!showBasedOnMeals || basedOnMeals == nil) {
//                RecordViewController.estimatePerTime(for: record.date)
//                DispatchQueue.main.async {
//                    self.graphView.prediction = Storage.default.calculatedLevel(for: record)
//                }
//            }
        }
        self.lastTouchedRecord = record
        DispatchQueue.main.after(withDelay: 3, closure: {
            self.lastTouchedRecord = nil
        })
    }
}
