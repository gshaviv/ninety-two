//
//  ViewController.swift
//  WoofWoof
//
//  Created by Guy on 14/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import UIKit
import Sqlable

class ViewController: UIViewController {
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var currentGlucoseLabel: UILabel!
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
    private var updater: Repeater?
    private var timeSpan = [24.h, 12.h, 6.h, 4.h, 2.h, 1.h]
    private var last24hReadings: [GlucoseReading] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        update()
        MiaoMiao.delgate = self
        timeSpanSelector.selectedSegmentIndex = UserDefaults.standard.timeSpanIndex
        graphView.xTimeSpan = timeSpan[UserDefaults.standard.timeSpanIndex]
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        agoLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .medium)
    }

    @IBAction func selectedTimeSpan(_ sender: UISegmentedControl) {
        UserDefaults.standard.timeSpanIndex = sender.selectedSegmentIndex
        graphView.xTimeSpan = timeSpan[sender.selectedSegmentIndex]
    }

    func update() {
        if let last = UserDefaults.standard.last {
            let end =  Date().timeIntervalSince(last) < 12.h  ? Date() : last
            if last24hReadings.isEmpty {
                if let readings = MiaoMiao.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > end - 1.d).orderBy(GlucosePoint.date)),
                    let calibrations = MiaoMiao.db.evaluate(Calibration.read().filter(Calibration.date > last - 1.d)) {
                    if calibrations.isEmpty {
                        last24hReadings = readings
                    } else {
                        var rIdx = 0
                        var cIdx = 0
                        var together = [GlucoseReading]()
                        repeat {
                            if readings[rIdx].date < calibrations[cIdx].date {
                                together.append(readings[rIdx])
                                rIdx += 1
                            } else {
                                together.append(calibrations[cIdx])
                                cIdx += 1
                            }
                        } while rIdx < readings.count && cIdx < calibrations.count
                        if rIdx < readings.count {
                            readings[rIdx...].forEach { together.append($0) }
                        }

                        last24hReadings = together
                    }
                }
            } else {
                while last24hReadings[0].date < Date() - 24.h {
                    _ = last24hReadings.dropFirst()
                }
            }
            var together = last24hReadings
            let trendData = MiaoMiao.trend ?? []
            if var latest = last24hReadings.last {
                for point in trendData.reversed() {
                    if (point.date > latest.date + 5.m && point.date < trendData.first!.date - 5.m) || point == trendData.first {
                        together.append(point)
                        latest = point
                    }
                }
            }

            graphView.points = together
            graphView.yRange.max = max(graphView.yRange.max, 180)
            graphView.yRange.min = min(graphView.yRange.min, 60)
            if !together.isEmpty {
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
        if MiaoMiao.batteryLevel > 0 {
            batteryLevelLabel.text = "\(MiaoMiao.batteryLevel)%"
        } else {
            batteryLevelLabel.text = "?%"
        }
        updater = Repeater.every(1, queue: DispatchQueue.main) { (_) in
            self.updateTimeAgo()
        }
        if let age = MiaoMiao.sensorAge {
            sensorAgeLabel.text = "\(age/24/60)d:\(age / 60 % 24)h"
        } else {
            sensorAgeLabel.text = "?"
        }
        if let trend = trend {
            trendLabel.text = String(format: "%@%.1lf", trend > 0 ? "+" : "", trend)
        } else {
            trendLabel.text = ""
        }
        do {
            let child = try MiaoMiao.db.createChild()
            DispatchQueue.global().async {
                if let readings = child.evaluate(GlucosePoint.read().filter(GlucosePoint.date > Date() - 90.d).orderBy(GlucosePoint.date)), !readings.isEmpty {
                    let diffs = readings.map { $0.date.timeIntervalSince1970 }.diff()
                    let withTime = zip(readings.dropLast(), diffs)
                    let withGoodTime = withTime.filter { $0.1 < 20.m }
                    let (sumG,totalT, timeBelow, timeIn, timeAbove) = withGoodTime.reduce((0.0,0.0,0.0,0.0,0.0)) { (result, arg) -> (Double,Double,Double,Double,Double) in
                        let (sum, total, below, inRange, above) = result
                        let (gp, duration) = arg
                        let x0 = sum + gp.value * duration
                        let x1 = total + duration
                        let x2 = gp.value < 70 ? below + duration : below
                        let x3 = gp.value >= 70 && gp.value < 140 ? inRange + duration : inRange
                        let x4 = gp.value >= 140 ? above + duration : above
                        return (x0, x1, x2 , x3, x4)
                    }
                    let aveG = sumG / totalT
                    let a1c = (aveG / 18.05 + 2.52) / 1.583
                    DispatchQueue.main.async {
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
        } catch _ { }
    }

    private func updateTimeAgo() {
        if let current = MiaoMiao.currentGlucose {
            let time = Int(round(Date().timeIntervalSince(current.date)))
            agoLabel.text = String(format: "%ld:%02ld Ago", time / 60, time % 60)
        } else {
            agoLabel.text = ""
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
                    try MiaoMiao.db.perform(c.insert())
                    UserDefaults.standard.additionalSlope *= bg / current.value
                    self.currentGlucoseLabel.text = "\(Int(round(bg)))\(self.trendSymbol(for: self.trendValue()))"
                    UIApplication.shared.applicationIconBadgeNumber = Int(round(bg))

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
        guard let trend = MiaoMiao.trend else {
            return nil
        }
        let diffs = trend.map { $0.value }.diff()
        if diffs.count > 4 {
            let ave = diffs[0 ..< 4].reduce(0) { $1 == 0 ? $0 : ($1 + $0) / 2 }
            return -ave
        }
        return nil
    }

    private func trendSymbol(for trend: Double?) -> String {
        guard let trend = trend else {
            return ""
        }
        if trend > 3 {
            return "⇈"
        } else if trend > 1.5 {
            return "↑"
        } else if trend > 0.75 {
            return "↗︎"
        } else if trend > -0.75 {
            return "→"
        } else if trend > -1.5 {
            return "↘︎"
        } else if trend > -3 {
            return "↓"
        } else {
            return "⇊"
        }
    }
}

extension ViewController: MiaoMiaoDelegate {
    func didUpdate() {
        if UIApplication.shared.applicationState != .background {
            update()
        } else {
            log("skipping cause in background")
        }
    }
}

