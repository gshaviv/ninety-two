//
//  SummaryViewController.swift
//  WoofWoof
//
//  Created by Guy on 24/02/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit
import Sqlable

class SummaryViewController: UIViewController {
    @IBOutlet var lowCountLabel: UILabel!
    @IBOutlet var summaryPeriodLabel: UILabel!
    @IBOutlet var percentLowLabel: UILabel!
    @IBOutlet var aveGlucoseLabel: UILabel!
    @IBOutlet var percentInRangeLabel: UILabel!
    @IBOutlet var a1cLabel: UILabel!
    @IBOutlet var percentHighLabel: UILabel!
    @IBOutlet var pieChart: PieChart!
    @IBOutlet var stackView: UIStackView!
    @IBOutlet var maxLabel: UILabel!
    @IBOutlet var minLabel: UILabel!
    @IBOutlet var medianLowLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        preferredContentSize = stackView.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width, height: 0), withHorizontalFittingPriority: UILayoutPriority.required, verticalFittingPriority: UILayoutPriority.fittingSizeLevel)
        updateSummary()
    }
    

    @objc public func updateSummary() {
        do {
            defaults[.lastStatisticsCalculation] = Date()
            let child = try Storage.default.db.createChild()
            var lowCount = 0
            var inLow = false
            summaryPeriodLabel.text = "Last \(defaults.summaryPeriod == 1 ? 24 : defaults.summaryPeriod) \(defaults.summaryPeriod > 1 ? "Days" : "Hours")"
            DispatchQueue.global().async {
                var lowStart: Date?
                var lowTime = [TimeInterval]()
                if let readings = child.evaluate(GlucosePoint.read().filter(GlucosePoint.date > Date() - defaults.summaryPeriod.d).orderBy(GlucosePoint.date)), !readings.isEmpty {
                    let diffs = readings.map { $0.date.timeIntervalSince1970 }.diff()
                    let withTime = zip(readings.dropLast(), diffs)
                    let withGoodTime = withTime.filter { $0.1 < 20.m }
                    var previousPoint: GlucosePoint?
                    var bands = [UserDefaults.ColorKey: TimeInterval]()
                    var maxG:Double = 0
                    var minG:Double = 9999
                    let (sumG, totalT, timeBelow, timeIn, timeAbove) = withGoodTime.reduce((0.0, 0.0, 0.0, 0.0, 0.0)) { (result, arg) -> (Double, Double, Double, Double, Double) in
                        let (sum, total, below, inRange, above) = result
                        let (gp, duration) = arg
                        let x0 = sum + gp.value * duration
                        let x1 = total + duration
                        let x2 = gp.value < defaults[.minRange] ? below + duration : below
                        let x3 = gp.value >= defaults[.minRange] && gp.value < defaults[.maxRange] ? inRange + duration : inRange
                        let x4 = gp.value >= defaults[.maxRange] ? above + duration : above
                        maxG = max(maxG, gp.value)
                        minG = min(minG, gp.value)
                        if gp.value >= defaults[.minRange] && gp.value < defaults[.maxRange] {
                            let key: UserDefaults.ColorKey
                            switch gp.value {
                            case ...defaults[.level0]:
                                key = .color0
                            case ...defaults[.level1]:
                                key = .color1
                            case ...defaults[.level2]:
                                key = .color2
                            case ...defaults[.level3]:
                                key = .color3
                            case ...defaults[.level4]:
                                key = .color4
                            default:
                                key = .color5
                            }
                            if let time = bands[key] {
                                bands[key] = time + duration
                            } else {
                                bands[key] = duration
                            }
                        }
                        if gp.value < defaults[.minRange] {
                            if !inLow {
                                lowCount += 1
                                if let previous = previousPoint {
                                    let d = previous.date + (previous.value - defaults[.minRange]) / (previous.value - gp.value) * (gp.date - previous.date)
                                    lowStart = d
                                } else {
                                    lowStart = gp.date
                                }
                            }
                            inLow = true
                        } else {
                            if inLow, let lowStart = lowStart {
                                if let previous = previousPoint {
                                    let d = previous.date + (defaults[.minRange] - previous.value) / (gp.value - previous.value) * (gp.date - previous.date)
                                    lowTime.append(d - lowStart)
                                } else {
                                    lowTime.append(gp.date - lowStart)
                                }
                            }
                            inLow = false
                        }
                        previousPoint = gp
                        return (x0, x1, x2, x3, x4)
                    }
                    let aveG = sumG / totalT
                    let a1c = (aveG / 18.05 + 2.52) / 1.583
                    let medianLowTime = lowTime.isEmpty ? 0 : Int(lowTime.sorted().median() / 1.m)
                    DispatchQueue.main.async {
                        let medianTime =  medianLowTime < 60 ?  String(format: "%ldm", medianLowTime) : String(format: "%ld:%02ld",medianLowTime / 60, medianLowTime % 60)
                        self.lowCountLabel.text = "\(lowCount)"
                        self.medianLowLabel.text = medianTime
                        self.maxLabel.text = maxG.formatted(with: "%.0lf")
                        self.minLabel.text = minG.formatted(with: "%.0lf")
                        self.percentLowLabel.text = String(format: "%.1lf%%", timeBelow / totalT * 100)
                        self.percentInRangeLabel.text = String(format: "%.1lf%%", timeIn / totalT * 100)
                        self.percentHighLabel.text = String(format: "%.1lf%%", timeAbove / totalT * 100)
                        self.aveGlucoseLabel.text = "\(Int(round(aveG)))"
                        self.a1cLabel.text = String(format: "%.1lf%%", a1c)
                        var slices = [UserDefaults.ColorKey.color0,
                                      UserDefaults.ColorKey.color1,
                                      UserDefaults.ColorKey.color2,
                                      UserDefaults.ColorKey.color3,
                                      UserDefaults.ColorKey.color4].compactMap { (key: UserDefaults.ColorKey) -> PieChart.Slice? in
                                        if let v = bands[key] {
                                            return PieChart.Slice(value: CGFloat(v), color: defaults[key])
                                        } else {
                                            return nil
                                        }
                        }
                        slices += [PieChart.Slice(value: CGFloat(timeAbove), color: .yellow), PieChart.Slice(value: CGFloat(timeBelow), color: .red)]
                        self.pieChart.slices = slices
                    }
                }
            }
        } catch {}
    }


}
