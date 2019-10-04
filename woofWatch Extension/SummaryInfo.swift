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
    let a1c: Double
    struct Low: Codable {
        let count: Int
        let median: Int
    }
    let low: Low
    let atdd: Double
    let timeInLevel: [TimeInterval]
}

class SummaryInfo: ObservableObject {
    @Published var data: Summary
    public init(_ summary: Summary) {
        data = summary
    }
    
    #if os(iOS)
    private(set) public var calcDate: Date? = nil
    
    public func updateSummary(force: Bool = false, completion: ((Bool)->Void)? = nil) {
        guard force || data == nil || Date() > date! + min(max(3.h, defaults.summaryPeriod.d / 50), 6.h) else {
            completion?(false)
            return
        }
        if force && Date() < calcDate + 1.h {
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
                calcDate = Date()
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
                    let rangeTime = Summary.TimeInRange(low: timeBelow, inRange: totalT - timeBelow - timeAbove, high: timeAbove)
                    let lows = Summary.Low(count: lowCount, median: medianLowTime)
                    let summary = Summary(period: defaults.summaryPeriod,
                                          timeInRange: rangeTime,
                                          maxLevel: maxG,
                                          minLevel: minG,
                                          average: aveG,
                                          a1c: a1c,
                                          low: lows,
                                          atdd: averageBolus,
                                          timeInLevel: [
                                            bands[UserDefaults.ColorKey.color0] ?? 0,
                                            bands[UserDefaults.ColorKey.color1] ?? 0,
                                            bands[UserDefaults.ColorKey.color2] ?? 0,
                                            bands[UserDefaults.ColorKey.color3] ?? 0,
                                            bands[UserDefaults.ColorKey.color4] ?? 0,
                                            bands[UserDefaults.ColorKey.color5] ?? 0,
                    ])
                    self.data = summary
                    completion?(true)
                }
            }
        } catch {}
    }
    #endif
}