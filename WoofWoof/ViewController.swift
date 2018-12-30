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
    private var updater: Repeater!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        update()
        MiaoMiao.delgate = self
        updater = Repeater.every(10, queue: DispatchQueue.main) { (_) in
            self.updateTimeAgo()
        }
        graphView.xTimeSpan = 5.h
    }

    func update() {
        if let last = UserDefaults.standard.last {
            if let readings = MiaoMiao.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > last - 1.d).orderBy(GlucosePoint.date)) {
                graphView.points = readings
                graphView.yRange.max = max(graphView.yRange.max, 180)
                graphView.yRange.min = min(graphView.yRange.min, 60)
                if !readings.isEmpty {
                    graphView.xRange.max = readings.last!.date
                    graphView.xRange.min = graphView.xRange.max - 24.h
                }
            }
        }
        if let current = MiaoMiao.currentGlucose {
            currentGlucoseLabel.text = "\(Int(round(current.value)))"
            agoLabel.text = "0 Ago"
            UIApplication.shared.applicationIconBadgeNumber = Int(round(current.value))
        } else {
            currentGlucoseLabel.text = "--"
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        if MiaoMiao.batteryLevel > 0 {
            batteryLevelLabel.text = "\(MiaoMiao.batteryLevel)%"
        } else {
            batteryLevelLabel.text = "?%"
        }
        if let age = MiaoMiao.sensorAge {
            sensorAgeLabel.text = "\(age/24/60)d:\(age / 60 % 24)h"
        } else {
            sensorAgeLabel.text = "?"
        }
        if let trend = MiaoMiao.currentTrend {
            trendLabel.text = String(format: "%@%.1lf", trend > 0 ? "+" : "-", trend)
        } else {
            trendLabel.text = ""
        }
        do {
            let child = try MiaoMiao.db.createChild()
            DispatchQueue.global().async {
                if let readings = child.evaluate(GlucosePoint.read().filter(GlucosePoint.date > Date() - 90.d).orderBy(GlucosePoint.date)) {
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
}

extension ViewController: MiaoMiaoDelegate {
    func didUpdate() {
        update()
    }


}

