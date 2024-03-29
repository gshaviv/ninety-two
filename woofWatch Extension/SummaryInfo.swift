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
import GRDB
#endif

struct Summary: Codable {
    struct Marks: OptionSet {
        let rawValue: Int
        
        static let none = Marks(rawValue: 1)
        static let seperator = Marks(rawValue: 1 << 1)
        static let bottomText = Marks(rawValue: 1 << 2)
        static let mark = Marks(rawValue: 1 << 3)
    }
    struct Daily: Codable {
        let average: Double
        let dose: Int
        let lows: Int
        let date: Date
        let percentLow: Double
        let percentHigh: Double
        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(average.decimal(digits: 2))
            try container.encode(dose)
            try container.encode(lows)
            try container.encode(date.timeIntervalSince1970.decimal(digits: 0))
            try container.encode(percentLow.decimal(digits: 0))
            try container.encode(percentHigh.decimal(digits: 0))
        }
        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            average = try container.decode(Double.self)
            dose = try container.decode(Int.self)
            lows = try container.decode(Int.self)
            let interval = try container.decode(Double.self)
            date = Date(timeIntervalSince1970: interval)
            percentLow = try container.decode(Double.self)
            percentHigh = try container.decode(Double.self)
        }
        init(average: Double, dose: Int, lows: Int, date: Date, percentLow: Double, percentHigh: Double) {
            self.average = average
            self.dose = dose
            self.date = date
            self.lows = lows
            self.percentHigh = percentHigh
            self.percentLow = percentLow
        }
    }
    let period: Int
    let actualPeriod: Int
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
    let daily: [Daily]
    let date: Date
    public var dateString: String {
        switch Date() - date {
        case 0 ..< 5.m:
            return "Just now"
            
        case 5.m ..< 1.h:
            return "\(Int((Date() - date) / 1.m)) minutes ago"
            
        case 1.h ..< 12.h:
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: date)
            
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
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
        guard defaults.summaryPeriod != data.period || force || Date() > calcDate + min(max(1.h, defaults.summaryPeriod.d / 50), 3.h) else {
            logError("No summary update, too frequent")
            completion?(false)
            return
        }
        if Date() < calcDate + 1.h && defaults.summaryPeriod == data.period {
            logError("No update, less than 1h")
            completion?(false)
            return
        }
        var lowCount = 0
        var inLow = false
        DispatchQueue.global().async {
            do {
                MiaoMiao.flushToDatabase()
                var lowStart: Date?
                var lowTime = [TimeInterval]()
                let readings = try Storage.default.db.read {
                    try GlucosePoint.filter(GlucosePoint.Column.date >  min(Date().startOfDay - defaults.summaryPeriod.d, Date().startOfDay - 90.d)).order(GlucosePoint.Column.date).fetchAll($0)
                }
                guard  !readings.isEmpty else {
                    completion?(false)
                    return
                }
                let actualPeriod = min(Int(ceil((Date().startOfDay - readings.first!.date) / 1.d)), defaults.summaryPeriod)
                let entries = Storage.default.allEntries.filter { $0.date > Date().startOfDay - 90.d  }
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
                var countG = 0
                var countLow = false
                var profile7 = [Double]()
                var found = false
                var sum90 = Double(0)
                var total90 = Double(0)
                var count90 = 0
                var daySum: (glucose:[Double], lows: Int) = ([],0)
                var perDay = [Summary.Daily]()
                var lastDay = -1
                var dayStart = Date.distantPast
                var dailyRange = (total: 0, low: 0, high: 0)
                readings.forEach { gp in
                    defer {
                        previousPoint = gp
                    }
                    
                    if let previous = previousPoint {
                        let duration = gp.date - previous.date
                        guard duration < 1.h else {
                            return
                        }
                        if gp.date > Date() - 90.d {
                            if gp.date.hour < 7 {
                                found = false
                            }
                            if !found && gp.date.hour == 23 {
                                found = true
                                profile7.append(gp.value)
                            }
                            if duration > 5.m {
                                sum90 += gp.value
                                total90 += duration
                                count90 += 1
                            }
                            switch (previous.value, gp.value) {
                            case (..<70, ..<70):
                                timeBelow70 += duration
                                
                            case (_, ..<70):
                                timeBelow70 += duration * (70 - gp.value) / (previous.value - gp.value)
                                
                            case (..<70, _):
                                timeBelow70 += duration * (70 - previous.value) / (gp.value - previous.value)
                                
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
                        }
                        
                        if gp.date > Date().startOfDay - defaults.summaryPeriod.d {
                            if gp.date.day != lastDay {
                                if !daySum.glucose.isEmpty, gp.date - dayStart > 23.h  {
                                    let units = entries.filter { $0.date > dayStart && $0.date < gp.date }.reduce(0) { $0 + $1.bolus }
                                    perDay.append(Summary.Daily(average: daySum.glucose.average(), dose: units, lows: daySum.lows, date: previous.date, percentLow: Double(dailyRange.low) / Double(dailyRange.total) * 100, percentHigh: Double(dailyRange.high) / Double(dailyRange.total) * 100))
                                }
                                lastDay = gp.date.day
                                daySum = ([],0)
                                dayStart = gp.date
                                dailyRange = (0,0,0)
                            }
                            daySum.glucose.append(gp.value)
                            dailyRange.total += 1
                            switch gp.value {
                            case defaults[.maxRange]...:
                                dailyRange.high += 1
                                
                            case ...(defaults[.minRange] - 3):
                                dailyRange.low += 1
                                
                            default:
                                break
                            }
                        }
                        
                        if gp.date > Date() - defaults.summaryPeriod.d {
                            if duration > 5.m {
                                sumG += gp.value
                                countG += 1
                                totalT += duration
                            }
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
                                    daySum.lows += 1
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
                    } else {
                        lastDay = gp.date.day
                    }
                }
                if !daySum.glucose.isEmpty {
                    let units = entries.filter { $0.date > dayStart }.reduce(0) { $0 + $1.bolus }
                    perDay.append(Summary.Daily(average: daySum.glucose.average(), dose: units, lows: daySum.lows, date:  readings.last?.date ?? Date(), percentLow: Double(dailyRange.low) / 24 / 4 * 100, percentHigh: Double(dailyRange.high) / 24 / 4 * 100))
                }
                let relevantMeals = entries.filter { $0.type != .other && $0.isMeal }
                if !relevantMeals.isEmpty {
                    let interp = AkimaInterpolator(points: readings.map { CGPoint(x: $0.date.timeIntervalSince1970, y: $0.value) })
                    relevantMeals.forEach {
                        if $0.date < readings.last!.date {
                            profile7.append(Double(interp.interpolateValue(at: CGFloat($0.date.timeIntervalSince1970))))
                            let after = $0.date + 90.m
                            if after < readings.last!.date {
                                profile7.append(Double(interp.interpolateValue(at: CGFloat(after.timeIntervalSince1970))))
                            }
                        }
                    }
                }
                
                let averageBolus = perDay.dropLast().map { Double($0.dose) }.average()
                
                let aveG = sumG / Double(countG)
                let ave90 = sum90 / Double(count90)
                // a1c estimation formula based on CGM data: https://care.diabetesjournals.org/content/41/11/2275
                let a1c = 3.31 + ave90 * 0.02392 // (aveG + 46.7) / 28.7 //(aveG / 18.05 + 2.52) / 1.583
                let ave7 = profile7.average()
                //                let a1c2 = (aveG + 46.7) / 28.7
                let a1c3 = (ave7 + 46.7) / 28.7
                let a1c31 = (ave90 + 46.7) / 28.7
                lowTime = lowTime.filter { !$0.isNaN }
                let medianLowTime = lowTime.isEmpty ? 0 : Int(lowTime.sorted().median() / 1.m)
                let timeBelow = lowTime.sum()
                let tir = (total90 - timeBelow70 - timeAbove180) / total90 * 100
                // a1c relationhip to TIR from: https://academic.oup.com/jes/article/3/Supplement_1/SAT-126/5483093/
                let a1c4 = (157 - tir) / 12.9
                // based on estimates from: https://care.diabetesjournals.org/content/diacare/31/8/1473.full.pdf
                let a1c2 = (ave90 + 36.9) / 28
                let a1c5 = (ave7 + 50.7) / 29.1
                let a1c6 = (ave7 + 43.9) / 28.3
                //                let a1c7 = 3.38 + 0.02345 * ave90 // https://care.diabetesjournals.org/content/41/11/2275
                //                let a1c8 = 3.31 + ave90 * 0.02392
                let a1c9 = 3.15 + 0.02505 * ave90
                // formulas based on: http://diabetesupdate.blogspot.com/2006/12/formulas-equating-hba1c-to-average.html
                let a1c10 = (ave90 + 77.3) / 35.6
                //                let a1c11 = (ave90 + 86) / 33.3
                let a1c12 = (ave90 / 18.05 + 2.52) / 1.583
                let a1cValues = [a1c, a1c2, a1c3, a1c4, a1c5, a1c6,  a1c9, a1c10,  a1c12, a1c31].sorted()
                let a1cMed = a1cValues.median()
                let ea1c = Summary.EA1C(value: a1cMed, range: min(a1cValues.percentile(0.8) - a1cMed, a1cMed - a1cValues.percentile(0.2)), cgm: a1c, seven: a1c3, tir: a1c4)
                DispatchQueue.main.async {
                    let rangeTime = Summary.TimeInRange(low: timeBelow, inRange: totalT - timeBelow - timeAbove, high: timeAbove)
                    let lows = Summary.Low(count: lowCount, median: medianLowTime)
                    let summary = Summary(period: defaults.summaryPeriod,
                                          actualPeriod: actualPeriod,
                                          timeInRange: rangeTime,
                                          maxLevel: maxG,
                                          minLevel: minG,
                                          average: aveG,
                                          a1c: ea1c,
                                          low: lows,
                                          atdd: averageBolus,
                                          timeInLevel: [bands[0] ?? 0,
                                                        bands[1] ?? 0,
                                                        bands[2] ?? 0,
                                                        bands[3] ?? 0,
                                                        bands[4] ?? 0,
                                                        bands[5] ?? 0],
                                          daily: perDay,
                                          date:  Date())
                    self.data = summary
                    completion?(true)
                }
            } catch {
                completion?(false)
            }
        }
    }
    #endif
}
