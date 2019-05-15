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
        guard defaults[.parameterCalcDate] != nil, record.carbs > 0 else {
            return nil
        }
        let bolus = Double(record.bolus)
        let date = record.date
        let when = date + (defaults[.delayMinutes] + defaults[.diaMinutes]) * 1.m
        let iob = insulinOnBoard(at: date - 1.s)
        let current: Double
        if let level = currentLevel {
            current = level
        } else {
            let readings = db.evaluate(GlucosePoint.read().filter(GlucosePoint.date < record.date + 1.h && GlucosePoint.date > record.date - 1.h).orderBy(GlucosePoint.date)) ?? []
            if readings.isEmpty {
                current = 0
            } else if let last = readings.last, last.date < record.date {
                current = last.value
            } else {
                let points = readings.map { CGPoint(x: $0.date.timeIntervalSince1970, y: $0.value) }
                let interp = AkimaInterpolator(points: points)
                current = Double(interp.interpolateValue(at: CGFloat(record.date.timeIntervalSince1970)))
            }
        }


        let predictedValue = current + max(0,record.carbs - defaults[.carbThreshold]) * defaults[.carbRate] - defaults[.insulinRate] * (bolus + iob)
        let highest = current + max(0,record.carbs * 1.1 - defaults[.carbThreshold]) * defaults[.carbRate] * 1.05 - defaults[.insulinRate] * (bolus + iob)
        let lowest = current + max(0,record.carbs * 0.9 - defaults[.carbThreshold] * 1.05) * defaults[.carbRate] * 0.95 - 1.05 * defaults[.insulinRate] * (bolus + iob)
        if predictedValue < 50 || lowest < 40 {
            return nil
        }
        return Prediction(count: 0, mealTime: record.date, highDate: when, h10: max(40,CGFloat(lowest)), h50: max(40,CGFloat(predictedValue)), h90: max(40,CGFloat(highest)), low50: 0, low: 0)
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

    public func relevantMeals(to record: Record) -> [(Record, Date)] {
        var possibleRecords = [(Record,Date)]()
        guard let note = record.note else {
            return []
        }

        let timeframe = defaults[.diaMinutes] * 60 + defaults[.delayMinutes] * 60
        for (idx, meal) in allEntries.enumerated() {
            guard meal.date < record.date else {
                break
            }
            guard meal.note == note else {
                continue
            }
            guard meal.type != nil && meal.id != record.id   else {
                continue
            }
            guard meal.carbs == record.carbs || meal.carbs == 0 || record.carbs == 0 else {
                continue
            }
            var endTime = meal.date + 5.h
            var extra = 0
            if idx < allEntries.count - 1 {
                for fixup in allEntries[(idx+1)...] {
                    guard fixup.date < endTime || fixup.type == nil else {
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
            if let low = db.evaluate(GlucosePoint.read().filter(GlucosePoint.value < 70 && GlucosePoint.date > meal.date && GlucosePoint.date < endTime)), !low.isEmpty {
                continue
            }
            possibleRecords.append((Record(id: meal.id, date: meal.date, meal: meal.type, bolus: meal.bolus + extra, note: meal.note), endTime))
        }
        let ionstart = insulinOnBoard(at: record.date - 1.s)
        let meals = possibleRecords.filter { abs(Double($0.0.bolus) + $0.0.insulinOnBoardAtStart - Double(record.bolus) - ionstart) < 0.5 }
        if meals.count > 12 {
            return Array(meals.sorted(by: { $0.0.date > $1.0.date })[0 ..< 12])
        }
        return meals
    }
    public func prediction(for record: Record, current level: Double? = nil) -> Prediction? {
        let readings = db.evaluate(GlucosePoint.read().filter(GlucosePoint.date < record.date).orderBy(GlucosePoint.date)) ?? []
        let current: GlucosePoint
        if let level = level {
            current = GlucosePoint(date: Date(), value: level)
        } else if let last = readings.last {
            current = last
        } else {
            return nil
        }
        if record.isMeal {
            let relevantMeals = self.relevantMeals(to: record)
            var points = [[GlucosePoint]]()
            guard !relevantMeals.isEmpty else {
                return nil
            }
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
            let predictedHigh = CGFloat(round(highs.sorted().median() + current.value))
            let predictedHigh25 = CGFloat(round(highs.sorted().percentile(0.1) + current.value))
            let predictedHigh75 = CGFloat(round(highs.sorted().percentile(0.9) + current.value))
            let predictedLow = CGFloat(round(lows.sorted().percentile(0.1) + current.value))
            let predictedLow50 = CGFloat(round(lows.sorted().median() + current.value))
            let predictedTime = record.date + timeToHigh.sorted().median()
            return Prediction(count: relevantMeals.count, mealTime: record.date, highDate: predictedTime, h10: predictedHigh25, h50: predictedHigh, h90: predictedHigh75, low50: predictedLow50, low: predictedLow)
        } else if let s = estimateInsulinReaction() {
            return Prediction(count: 0, mealTime: record.date, highDate: record.date, h10: 0, h50: 0, h90: 0, low50: CGFloat(current.value - s * Double(record.bolus)), low: CGFloat(current.value - s * Double(record.bolus)))
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
        let dia = defaults[.diaMinutes] * 60
        let records = db.evaluate(Record.read().filter(Record.bolus > 0 && Record.date > date - dia - defaults[.delayMinutes])) ?? []
        if records.isEmpty {
            return 0
        }
        return records.reduce(0) { $0 + $1.insulinAction(at: date).iob }
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

