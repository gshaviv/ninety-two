//
//  Storage.swift
//  WoofKit
//
//  Created by Guy on 18/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import Sqlable


public class Storage: NSObject {
    public static let `default` = Storage()
    internal var lockfile: URL = {
        let url = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "lockfile"))
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "lock".write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }()
    public let dbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "read.sqlite"))
    public var db: SqliteDatabase = {
        let dbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "read.sqlite"))
        log("dbURL = \(dbUrl)")
        let db = try! SqliteDatabase(filepath: dbUrl.path)
        db.queue = DispatchQueue(label: "db")
        try! db.createTable(GlucosePoint.self)
        try! db.createTable(Calibration.self)
        try! db.createTable(Record.self)
        try! db.createTable(ManualMeasurement.self)
        try? db.execute("PRAGMA journal_mode = DELETE")
        return db
    }()
    public let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    private(set) public var lastDay = Today()
    public func reloadToday() {
        lastDay = Today()
        _allEntries = nil
    }
    private var _allEntries: [Record]? = nil
    public var allEntries: [Record] {
        if _allEntries == nil {
            _allEntries = db.evaluate(Record.read().orderBy(Record.date))
        }
        return _allEntries ?? []
    }
    public var allMeals: [Record] {
        return allEntries.filter { $0.isMeal }
    }
    @objc private func didReceiveMemoryWarning() {
        _allEntries = nil
        lastDay = Today()
    }

    public func calculatedLevel(for record: Record, currentLevel: Double? = nil) -> Prediction? {
        guard defaults[.parameterCalcDate] != nil && (record.isBolus || record.carbs > 0) else {
            return nil
        }
        let bolus = Double(record.bolus) + record.insulinOnBoardAtStart
        let carbs = record.carbs + record.cobOnStart
        let current: Double
        if let level = currentLevel {
            current = level
        } else {
            let readings = db.evaluate(GlucosePoint.read().filter(GlucosePoint.date < record.date  && GlucosePoint.date > record.date - 2.h).orderBy(GlucosePoint.date)) ?? []
            if let last = readings.last {
                current = last.value
            } else {
                return nil
            }
        }

        let high = CGFloat(carbs * defaults.param(.ch, at: record.date) - bolus * defaults.param(.ih, at: record.date) + current)
        let low = CGFloat(carbs * defaults.param(.cl,at: record.date) - bolus * defaults.param(.il, at: record.date) + current)
        let end = CGFloat(carbs * defaults.param(.ce,at: record.date) - bolus * defaults.param(.ie, at: record.date) + current)

        return Prediction(count: 0, mealTime: record.date, highDate: record.date + 2.h, h10: high - CGFloat(defaults.param(.hsigma, at: record.date) * 1.2), h50: high, h90: high + CGFloat(defaults.param(.hsigma, at: record.date) * 1.2), low50: min(low,end), low: min(low - CGFloat(defaults.param(.lsigma, at: record.date)), end - CGFloat(defaults.param(.esigma, at: record.date))))
    }
    


    public func estimateInsulinReaction() -> Double? {
        let boluses = allEntries.enumerated().compactMap { (arg) -> (record:Record, time:TimeInterval)? in
            guard arg.offset > 0 && arg.element.type == nil && arg.offset < allEntries.count - 1 else {
                return nil
            }
            if arg.element.date - allEntries[arg.offset - 1].date < 5.h  {
                return nil
            }
            return (record: arg.element, time: max((defaults[.diaMinutes] + defaults[.delayMinutes]) * 60, allEntries[arg.offset + 1].date - arg.element.date))
        }
        var impact = [Double]()
        for bolus in boluses {
            guard let readings = db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > bolus.record.date && GlucosePoint.date < bolus.record.date + bolus.time).orderBy(GlucosePoint.date)), !readings.isEmpty else {
                continue
            }
            let starting = readings.last { $0.date <  bolus.record.date + defaults[.delayMinutes] * 60 } ?? readings[0]
            let startInsulin = bolus.record.insulinAction(at: starting.date).iob
            for ending in readings {
            let insulinWorked = startInsulin - bolus.record.insulinAction(at: ending.date).iob
            guard insulinWorked > 1, ending.date > starting.date else {
                continue
            }
            let dropped = ending.value - starting.value
            guard dropped < 0, ending.value > 70 else {
                continue
            }
            impact.append(dropped / insulinWorked)
            }
        }

        guard !impact.isEmpty else {
            return nil
        }

        return impact.sum() / Double(impact.count)
    }
    
    public struct Datum : CustomStringConvertible {
        public let date: Date
        public let start: Double
        public let kind: String
        public fileprivate(set) var high: Double
        public fileprivate(set) var low: Double
        public let end: Double
        public fileprivate(set) var carbs: Double
        public fileprivate(set) var bolus: Double
        public let iob: Double
        public let cob: Double
        public fileprivate(set) var isComplete: Bool
        
        public var description: String {
            let formater = DateFormatter()
            formater.dateStyle = .short
            formater.timeStyle = .short
            formater.locale = Locale(identifier: "he_IL")
            formater.timeZone = TimeZone.current
            return "<Datum: carbs=\(carbs % "2.0lf") cob=\(cob) bolus=\(bolus) iob=\(iob) rise=\((high - start) % "2.0lf") drop=\((start - low) % "2.0lf") kind=\(kind) date=\(formater.string(from: date))>"
        }
    }
    
    public func mealData(includeBolus: Bool, includeMeal: Bool) -> [Datum] {
        var datum = [Datum]()
        let timeframe =  (defaults[.diaMinutes] + defaults[.delayMinutes]) * 60
        
        for (idx,entry) in allEntries.enumerated() {
            if !includeMeal {
                if entry.isMeal || entry.carbs > 0 {
                    continue
                }
            }
            if !includeBolus {
                if !entry.isMeal || entry.carbs == 0 {
                    continue
                }
            }
            guard Date() - entry.date < 180.d else {
                continue
            }
            if idx > 1 {
                let previousEntry = allEntries[idx - 1]
                if entry.date - previousEntry.date < timeframe {
                    continue
                }
            }
            
            var mealtime = timeframe
            var totalBolus = Double(entry.bolus)
            var skip = 0
            while true {
                if idx + skip + 1 < allEntries.count {
                    let nextEntry = allEntries[idx + skip + 1]
                    if nextEntry.date - entry.date > 5.h && mealtime < 5.h {
                        mealtime = 5.h
                        break
                    } else if nextEntry.date < entry.date + mealtime {
                        if nextEntry.isMeal {
                            mealtime = nextEntry.date - entry.date
                            totalBolus = Double(entry.bolus) - entry.insulinAction(at: nextEntry.date).iob
                            break
                        } else {
                            mealtime = nextEntry.date + mealtime - entry.date
                            totalBolus += Double(nextEntry.bolus)
                        }
                    }
                } else {
                    mealtime = 5.h
                    break
                }
                skip += 1
            }
           
            let readings = db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > entry.date - 15.m && GlucosePoint.date < entry.date + mealtime + 15.m).orderBy(GlucosePoint.date)) ?? []
            guard !readings.isEmpty, readings.last!.date - readings.first!.date > mealtime else {
                continue
            }
            let points = readings.map { CGPoint(x: $0.date.timeIntervalSince1970, y: $0.value) }
            let interp = AkimaInterpolator(points: points)
            
            var entryData = Datum(date: entry.date,
                                  start: Double(interp.interpolateValue(at: CGFloat(entry.date.timeIntervalSince1970))),
                                  kind: entry.type?.name ?? "bolus",
                                  high: 0,
                                  low: Double.greatestFiniteMagnitude,
                                  end: Double(interp.interpolateValue(at: CGFloat(entry.date.timeIntervalSince1970) + CGFloat(timeframe))),
                                  carbs: Double(entry.carbs),
                                  bolus: totalBolus,
                                  iob: entry.insulinOnBoardAtStart,
                                  cob: entry.cobOnStart,
                                  isComplete: mealtime >= timeframe)
            var last = readings.first!.date
            var isValid = true
            var inRange = false
            var timeOfLow = last
            for point in readings {
                let time = point.date
                if time - last > 30.m {
                    isValid = false
                    break
                }
                last = time
                if time < entry.date {
                    continue
                }
                let value = point.value
                if value > entryData.high {
                    entryData.high = value
                }
                if value < entryData.low {
                    entryData.low = value
                    timeOfLow = time
                }
                if value < defaults[.minRange] + 5 && inRange {
                    isValid = false
                    break
                }
                if value > defaults[.minRange] {
                    inRange = true
                }
            }
            
            guard entryData.start > 30 && entryData.end > 30 && entryData.high > 30 && entryData.low > 65  else {
                continue
            }
            if !isValid {
                if timeOfLow <= last {
                    entryData.isComplete = false
                } else {
                    continue
                }
            }
            if !entryData.isComplete {
                entryData.carbs *= mealtime / timeframe
                entryData.bolus -= entry.insulinAction(at: entry.date + mealtime).iob
//                continue // don't use incomplete meals
            }
            datum.append(entryData)
        }
        return datum
    }

    public func relevantMeals(to record: Record) -> [(Record, Date)] {
        var possibleRecords = [(Record,Date)]()
        guard let note = record.note else {
            return []
        }

        let timeframe = (defaults[.diaMinutes] + defaults[.delayMinutes]) * 60
        for (idx, meal) in allEntries.enumerated() {
            guard meal.date < record.date  else {
                break
            }
            guard meal.note == note  && meal.type != nil && meal.id != record.id   else {
                continue
            }
            guard meal.carbs == record.carbs || meal.carbs == 0 || record.carbs == 0 else {
                continue
            }
            var endTime = meal.date + 5.h
            var extra = 0
            if idx < allEntries.count - 1 {
                for fixup in allEntries[(idx+1)...] {
                    guard fixup.date < endTime  else {
                        break
                    }
                    if fixup.type != nil {
                        endTime = fixup.date
                        break
                    }
                    extra += fixup.bolus
                    endTime = max(endTime, fixup.date + timeframe)
                }
            }
            if endTime - meal.date < 3.h {
                continue
            }
            if let low = db.evaluate(GlucosePoint.read().filter(GlucosePoint.value < 70 && GlucosePoint.date > meal.date && GlucosePoint.date < endTime)), !low.isEmpty {
                continue
            }
            possibleRecords.append((Record(id: meal.id, date: meal.date, meal: meal.type, bolus: meal.bolus + extra, note: meal.note), endTime))
        }
        let meals = possibleRecords.filter { abs(Double($0.0.bolus) + $0.0.insulinOnBoardAtStart - Double(record.bolus) - record.insulinOnBoardAtStart) < 0.5 }
        if meals.count > 24 {
            return Array(meals.sorted(by: { $0.0.date > $1.0.date })[0 ..< 24])
        }
        return meals
    }

    public func prediction(for record: Record, current level: Double? = nil) -> Prediction? {
        let current: GlucosePoint
        let readings = db.evaluate(GlucosePoint.read().filter(GlucosePoint.date < record.date).orderBy(GlucosePoint.date)) ?? []
        if let level = level {
            current = GlucosePoint(date: Date(), value: level)
        } else {
            guard let last = readings.last else {
                return nil
            }
            current = last
        }
        if record.isMeal {
            let relevantMeals = self.relevantMeals(to: record)
            guard !relevantMeals.isEmpty else {
                return nil
            }
            if (record.carbs == 0.0 || record.mealId == nil) && relevantMeals.count < 3 {
                return nil
            }
            var points = [[GlucosePoint]]()

            for (meal, nextDate) in relevantMeals {
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
                let stat = mealStatistics(meal: meal.0, points: mealPoints)
                highs.append(stat.0)
                lows.append(stat.2)
                timeToHigh.append(stat.1)
            }
            guard !highs.isEmpty else {
                return nil
            }
            let average = highs.average()
            let stdDev = sqrt(highs.map { ($0 - average) ** 2 }.average())
            let averageLow = lows.average()
            let lowStdDev = sqrt(lows.map { ($0 - averageLow) ** 2 }.average())

            let predictedHigh = CGFloat(round(average + current.value))
            let predictedHigh25 = CGFloat(round(average - 1.5 * stdDev + current.value))
            let predictedHigh75 = CGFloat(round(average + 1.5 * stdDev + current.value))
            let predictedLow = CGFloat(round(averageLow + current.value - 1.5 * lowStdDev))
            let predictedLow50 = CGFloat(round(averageLow + current.value))
            let predictedTime = record.date + timeToHigh.sum() / Double(timeToHigh.count)
            
            return Prediction(count: highs.count, mealTime: record.date, highDate: predictedTime, h10: predictedHigh25, h50: predictedHigh, h90: predictedHigh75, low50: predictedLow50, low: predictedLow)
        } else {
            return nil
        }
    }
    public func mealStatistics(meal: Record, points mealPoints: [GlucosePoint]) -> (Double, TimeInterval, Double) {
        var highest = mealPoints[0]
        var lowestAfterHigh = mealPoints[0]
        for point in mealPoints[1...] {
            if point.value > highest.value {
                highest = point
                lowestAfterHigh = point
            } else if point.value < highest.value && point.value < lowestAfterHigh.value {
                lowestAfterHigh = point
            }
        }
        return (highest.value - mealPoints[0].value, highest.date - meal.date, lowestAfterHigh.value - mealPoints[0].value)
    }
    public func insulinOnBoard(at date: Date) -> Double {
        let dia = (defaults[.diaMinutes] + defaults[.delayMinutes]) * 60
        let records = allEntries.filter({ $0.isBolus && $0.date > date - dia })
        if records.isEmpty {
            return 0
        }
        return records.reduce(0) { $0 + $1.insulinAction(at: date).iob }
    }
    public func insulinAction(at date: Date) -> Double {
        insulinOnBoard(at: date) - insulinOnBoard(at: date + 10.m)
    }
    public func insulinHorizon() -> Date? {
        let dia = (defaults[.diaMinutes] + defaults[.delayMinutes]) * 60
        if let record = allEntries.filter({ $0.isBolus && $0.date > Date() - dia }).last {
            return record.date + dia
        }
        return nil
    }
    public override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMemoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMemoryWarning), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
}

public class Today {
    public lazy var entries: [Record] = {
        let limit = Date() - 1.d
        return Storage.default.db.evaluate(Record.read().filter(Record.date > limit).orderBy(Record.date)) ?? []
    }()
    public lazy var manualMeasurements: [ManualMeasurement] = {
        let limit = Date() - 1.d
        return Storage.default.db.evaluate(ManualMeasurement.read().filter(ManualMeasurement.date > limit).orderBy(ManualMeasurement.date)) ?? []
    }()
}



public struct StoredParames {
    fileprivate var paramValues: [String:Double]
    
    public subscript(key: UserDefaults.DoubleKey) -> Double {
        get {
            return paramValues[key.rawValue] ?? defaults[key] 
        }
        set {
            paramValues[key.rawValue] = newValue
        }
    }
    
    public static func empty() -> StoredParames {
        return StoredParames([:])
    }
    
    fileprivate init(_ values: [String:Double]) {
        paramValues = values
    }
}

public enum PartOfDay: String, CaseIterable {
    case night
    case morning
    case afternoon
    case evening
}

public extension Date {
    var partOfDay: PartOfDay {
        switch hour {
        case 4 ..< 11:
            return .morning
            
        case 11 ..< 17:
            return .afternoon
            
        case 17 ..< 23:
            return .evening
            
        default:
            return .night
        }
    }
}

public extension UserDefaults {
    subscript(when: PartOfDay) -> StoredParames? {
        get {
            if let values = defaults.value(forKey: when.rawValue) as? [String: Double] {
                return StoredParames(values)
            }
            return nil
        }
        set {
            defaults.set(newValue?.paramValues, forKey: when.rawValue)
        }
    }
    func param(_ key: UserDefaults.DoubleKey, at part: PartOfDay) -> Double {
        if let p = defaults[part] {
            return p[key]
        }
        return defaults[key]
    }
    func param(_ key: UserDefaults.DoubleKey, at date: Date) -> Double {
        return param(key, at: date.partOfDay)
    }
}

