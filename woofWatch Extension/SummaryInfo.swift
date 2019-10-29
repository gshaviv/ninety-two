//
//  SummaryInfo.swift
//  WoofWoof
//
//  Created by Guy on 30/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
#if os(iOS)
import WoofKit
import Sqlable
#endif

struct Summary: Codable {
    let period: Int
    struct TimeInRange: Codable {
        let low: TimeInterval
        let inRange: TimeInterval
        let high: TimeInterval
    }
    let timeInRange: TimeInRange
    var totalTime: TimeInterval {
        timeInRange.low + timeInRange.inRange + timeInRange.high
    }
    var percentTimeIn: Decimal {
        100 - percentTimeAbove - percentTimeBelow
    }
    var percentTimeBelow: Decimal {
        (100 * timeInRange.low / max(totalTime,1)).decimal(digits: 1)
    }
    var percentTimeAbove: Decimal {
        (100 * timeInRange.high / max(totalTime,1)).decimal(digits: 1)
    }
    let maxLevel: Double
    let minLevel: Double
    let average: Double
    struct EA1C: Codable {
        let value: Double
        let range: Double
        let cgm: Double
        let seven: Double
        let tir: Double
        
        public init(value: Double, range: Double, cgm: Double? = nil, seven: Double? = nil, tir: Double? = nil) {
            self.value = value
            self.range = range
            self.cgm = cgm ?? value + range
            self.seven = seven ?? value
            self.tir = tir ?? value - range
        }
    }
    let a1c: EA1C
    struct Low: Codable {
        let count: Int
        let median: Int
    }
    let low: Low
    let atdd: Double
    let timeInLevel: [TimeInterval]
}

class SummaryInfo: ObservableObject {
    private(set) public var calcDate: Date = Date.distantPast
    @Published var data: Summary {
        didSet {
            calcDate = Date()
        }
    }
    public init(_ summary: Summary) {
        data = summary
    }
    
    #if os(iOS)
    
    public func update(force: Bool = false, completion: ((Bool)->Void)? = nil) {
        guard defaults.summaryPeriod != data.period || force || Date() > calcDate + min(max(3.h, defaults.summaryPeriod.d / 50), 6.h) else {
            logError("No update, too frequent")
            completion?(false)
            return
        }
        if Date() < calcDate + 1.h && defaults.summaryPeriod == data.period {
            logError("No update, less than 1h")
            completion?(false)
            return
        }
        do {
            let child = try Storage.default.db.createChild()
            var lowCount = 0
            var inLow = false
            DispatchQueue.global().async {
                MiaoMiao.flushToDatabase()
                var lowStart: Date?
                var lowTime = [TimeInterval]()
                guard let readings = child.evaluate(GlucosePoint.read().filter(GlucosePoint.date > Date() - defaults.summaryPeriod.d).orderBy(GlucosePoint.date)), !readings.isEmpty else {
                    completion?(false)
                    return
                }
                let meals = Storage.default.allMeals.filter { $0.date > Date() - defaults.summaryPeriod.d && $0.type != .other }
                self.calcDate = Date()
                var previousPoint: GlucosePoint?
                var bands = [Int: TimeInterval]()
                var maxG:Double = 0
                var minG:Double = 9999
                var timeAbove = Double(0)
                var timeAbove180: Double = 0
                var timeBelow70: Double = 0
                var totalT = Double(0)
                var sumG = Double(0)
                var countLow = false
                var profile7 = [Double]()
                var found = false
                readings.forEach { gp in
                    defer {
                        previousPoint = gp
                    }
                    if let previous = previousPoint {
                        let duration = gp.date - previous.date
                        guard duration < 1.h else {
                            return
                        }
                        if gp.date.hour < 7 {
                            found = false
                        }
                        if !found && gp.date.hour == 23 {
                            found = true
                            profile7.append(gp.value)
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
                        switch (previous.value, gp.value) {
                        case (180..., 180...):
                            timeAbove180 += duration
                            
                        case (_, 180...):
                            timeAbove180 += duration * (gp.value - 180) / (gp.value - previous.value)
                            
                        case (180..., _):
                            timeAbove180 += duration * (previous.value - 180) / (previous.value - gp.value)
                            
                        default:
                            break
                        }
                        switch (previous.value, gp.value) {
                        case (..<70, ..<70):
                            timeBelow70 += duration
                            
                        case (_, ..<70):
                            timeAbove180 += duration * (70 - gp.value) / (previous.value - gp.value)
                            
                        case (..<70, _):
                            timeAbove180 += duration * (70 - previous.value) / (gp.value - previous.value)
                            
                        default:
                            break
                        }
                        
                        maxG = max(maxG, gp.value)
                        minG = min(minG, gp.value)
                        let key: Int
                        switch gp.value {
                        case ...defaults[.level0]:
                            key = 0
                        case ...defaults[.level1]:
                            key = 1
                        case ...defaults[.level2]:
                            key = 2
                        case ...defaults[.level3]:
                            key = 3
                        case ...defaults[.level4]:
                            key = 4
                        default:
                            key = 5
                        }
                        bands[key] = (bands[key] ?? 0) + duration
                        
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
                if !meals.isEmpty {
                    let interp = AkimaInterpolator(points: readings.map { CGPoint(x: $0.date.timeIntervalSince1970, y: $0.value) })
                    meals.forEach {
                        if $0.date < readings.last!.date {
                            profile7.append(Double(interp.interpolateValue(at: CGFloat($0.date.timeIntervalSince1970))))
                            let after = $0.date + 90.m
                            if after < readings.last!.date {
                                profile7.append(Double(interp.interpolateValue(at: CGFloat(after.timeIntervalSince1970))))
                            }
                        }
                    }
                }
                
                let start = (Date() - defaults.summaryPeriod.d).endOfDay
                let end = defaults.summaryPeriod > 1 ? Date().startOfDay : Date()
                let averageBolus = Storage.default.allEntries.filter { $0.date > start  && $0.date < end }.reduce(0.0) { $0 + Double($1.bolus) } / (end - start) * 1.d
                
                let aveG = sumG / totalT
                // a1c estimation formula based on CGM data: https://care.diabetesjournals.org/content/41/11/2275
                let a1c = 3.31 + aveG * 0.02392 // (aveG + 46.7) / 28.7 //(aveG / 18.05 + 2.52) / 1.583
                let ave7 = profile7.average()
//                let a1c2 = (aveG + 46.7) / 28.7
                let a1c3 = (ave7 + 46.7) / 28.7
                let medianLowTime = lowTime.isEmpty ? 0 : Int(lowTime.sorted().median() / 1.m)
                let timeBelow = lowTime.sum()
                let tir = (totalT - timeBelow70 - timeAbove180) / totalT * 100
                // a1c relationhip to TIR from: https://academic.oup.com/jes/article/3/Supplement_1/SAT-126/5483093/
                let a1c4 = (157 - tir) / 12.9
                // based on estimates from: https://care.diabetesjournals.org/content/diacare/31/8/1473.full.pdf
                let a1c2 = (aveG + 36.9) / 28
                let a1c5 = (ave7 + 50.7) / 29.1
                let a1c6 = (ave7 + 43.9) / 28.3
                let a1c7 = 3.38 + 0.02345 * aveG // https://care.diabetesjournals.org/content/41/11/2275
                let a1c8 = 3.31 + aveG * 0.02392
                let a1c9 = 3.15 + 0.02505 * aveG
                // formulas based on: http://diabetesupdate.blogspot.com/2006/12/formulas-equating-hba1c-to-average.html
                let a1c10 = (aveG + 77.3) / 35.6
                let a1c11 = (aveG + 86) / 33.3
                let a1c12 = (aveG / 18.05 + 2.52) / 1.583
                let a1cValues = [a1c, a1c2, a1c3, a1c4, a1c5, a1c6, a1c7, a1c8, a1c9, a1c10, a1c11, a1c12].sorted()
                let a1cMed = (a1cValues.percentile(0.75) + a1cValues.percentile(0.25)) / 2
                let ea1c = Summary.EA1C(value: a1cMed, range: a1cValues.percentile(0.75) - a1cMed, cgm: a1c, seven: a1c3, tir: a1c4)
                DispatchQueue.main.async {
                    let rangeTime = Summary.TimeInRange(low: timeBelow, inRange: totalT - timeBelow - timeAbove, high: timeAbove)
                    let lows = Summary.Low(count: lowCount, median: medianLowTime)
                    let summary = Summary(period: defaults.summaryPeriod,
                                          timeInRange: rangeTime,
                                          maxLevel: maxG,
                                          minLevel: minG,
                                          average: aveG,
                                          a1c: ea1c,
                                          low: lows,
                                          atdd: averageBolus,
                                          timeInLevel: [
                                            bands[0] ?? 0,
                                            bands[1] ?? 0,
                                            bands[2] ?? 0,
                                            bands[3] ?? 0,
                                            bands[4] ?? 0,
                                            bands[5] ?? 0,
                    ])
                    self.data = summary
                    completion?(true)
                }
            }
        } catch {}
    }
    #endif
}
