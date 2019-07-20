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
        NotificationCenter.default.addObserver(self, selector: #selector(updateSummary), name: UserDefaults.notificationForChange(UserDefaults.IntKey.summaryPeriod), object: nil)
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
//                    let diffs = readings.map { $0.date.timeIntervalSince1970 }.diff()
//                    let withTime = zip(readings.dropLast(), diffs)
//                    let withGoodTime = withTime.filter { $0.1 < 20.m }
                    var previousPoint: GlucosePoint?
                    var bands = [UserDefaults.ColorKey: TimeInterval]()
                    var maxG:Double = 0
                    var minG:Double = 9999
                    var timeAbove = Double(0)
                    var totalT = Double(0)
                    var sumG = Double(0)
                    var countLow = false
                    readings.forEach { gp in
                        defer {
                            previousPoint = gp
                        }
                        if let previous = previousPoint {
                            let duration = gp.date - previous.date
                            guard duration < 1.h else {
                                return
                            }
                            sumG += gp.value * duration
                            totalT += duration
                            switch (previous.value, gp.value) {
                            case (defaults[.maxRange]..., defaults[.maxRange]...):
                                timeAbove += duration

                            case (_, defaults[.maxRange]...):
                                timeAbove += duration * (gp.value - defaults[.maxRange]) / (gp.value - previous.value)

                            case (defaults[.maxRange]..., _):
                                timeAbove += duration * (previous.value - defaults[.maxRange]) / (previous.value - gp.value)

                            default:
                                break
                            }

                            maxG = max(maxG, gp.value)
                            minG = min(minG, gp.value)
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

                            if gp.value < defaults[.minRange] {
                                if !inLow {
                                    lowStart = previous.date + (previous.value - defaults[.minRange]) / (previous.value - gp.value) * (gp.date - previous.date)
                                    countLow = gp.value < defaults[.minRange] - 3
                                }
                                inLow = true
                                countLow = countLow || gp.value < defaults[.minRange] - 3
                            } else {
                                if inLow, let lowStart = lowStart, countLow {
                                    lowCount += 1
                                    let d = previous.date + (defaults[.minRange] - previous.value) / (gp.value - previous.value) * (gp.date - previous.date)
                                    lowTime.append(d - lowStart)
                                }
                                inLow = false
                            }
                        }
                    }

                    let start = (Date() - defaults.summaryPeriod.d).endOfDay
                    let end = defaults.summaryPeriod > 1 ? Date().startOfDay : Date()
                    let averageBolus = Storage.default.allEntries.filter { $0.date > start  && $0.date < end }.reduce(0.0) { $0 + Double($1.bolus) } / (end - start) * 1.d

                    let aveG = sumG / totalT
                    let a1c = (aveG / 18.05 + 2.52) / 1.583
                    let medianLowTime = lowTime.isEmpty ? 0 : Int(lowTime.sorted().median() / 1.m)
                    let timeBelow = lowTime.sum()
                    DispatchQueue.main.async {
                        let medianTime =  medianLowTime < 60 ?  String(format: "%ldm", medianLowTime) : String(format: "%ld:%02ld",medianLowTime / 60, medianLowTime % 60)
                        self.lowCountLabel.text = "\(lowCount)"
                        self.medianLowLabel.text = medianTime
                        self.maxLabel.text = "\(maxG % ".0lf") / \(minG % ".0lf")"
                        self.minLabel.text = averageBolus % ".1lfu"
                        self.percentLowLabel.text = String(format: "%.1lf%%", timeBelow / totalT * 100)
                        let percentIn = (1000 - round(timeBelow / totalT * 1000) - round(timeAbove / totalT * 1000))/10
                        self.percentInRangeLabel.text = String(format: "%.1lf%%", percentIn)
                        self.percentHighLabel.text = String(format: "%.1lf%%", timeAbove / totalT * 100)
                        self.aveGlucoseLabel.text = "\(Int(round(aveG)))"
                        self.a1cLabel.text = String(format: "%.1lf%%", a1c)
                        let slices = [UserDefaults.ColorKey.color0,
                                      UserDefaults.ColorKey.color1,
                                      UserDefaults.ColorKey.color2,
                                      UserDefaults.ColorKey.color3,
                                      UserDefaults.ColorKey.color4,
                                      UserDefaults.ColorKey.color5].compactMap { (key: UserDefaults.ColorKey) -> PieChart.Slice? in
                                        if let v = bands[key] {
                                            return PieChart.Slice(value: CGFloat(v), color: defaults[key])
                                        } else {
                                            return nil
                                        }
                        }
//                        slices += [PieChart.Slice(value: CGFloat(timeAbove), color: .yellow), PieChart.Slice(value: CGFloat(timeBelow), color: .red)]
                        self.pieChart.slices = slices
                    }
                }
            }
        } catch {}
    }

    @IBAction private func changePeriod() {
        let ctr = UIStoryboard(name: "Settings", bundle: nil).instantiateViewController(withIdentifier: "enum") as! EnumViewController
        ctr.count = UserDefaults.summaryPeriods.count
        ctr.title = "Summary Timeframe"
        ctr.value = defaults[.summaryPeriod]
        ctr.setter = {
            defaults[.summaryPeriod] = $0
        }
        ctr.getValue = {
            $0 == 0 ? "24 hours" : "\(UserDefaults.summaryPeriods[$0]) days"
        }
        present(ctr, animated: true, completion: nil)
    }

}
