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
    fileprivate var lockfile: URL = {
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
    }

    public func relevantMeals(to record: Record) -> [(Record, Date)] {
        var possibleRecords = [(Record,Date)]()

        let timeframe = defaults[.diaMinutes] * 60 + defaults[.delayMinutes] * 60
        for (idx, meal) in allEntries.enumerated() {
            guard meal.date < record.date else {
                break
            }
            guard meal.meal != nil && meal.id != record.id else {
                continue
            }
            var endTime = meal.date + 5.h
            var extra = 0
            if idx < allEntries.count - 1 {
                for fixup in allEntries[(idx+1)...] {
                    guard fixup.date < endTime || fixup.meal == nil else {
                        break
                    }
                    if fixup.meal != nil {
                        endTime = fixup.date
                        break
                    }
                    extra += fixup.bolus
                    endTime = max(endTime, fixup.date + timeframe)
                }
            }
            possibleRecords.append((Record(id: meal.id, date: meal.date, meal: meal.meal, bolus: meal.bolus + extra, note: meal.note), endTime))
        }
        let ionstart = record.insulinOnBoardAtStart
        let meals = possibleRecords.filter { abs(Double($0.0.bolus) + $0.0.insulinOnBoardAtStart - Double(record.bolus) - ionstart) < 1 }
        var relevantMeals = meals.filter { $0.0.meal == record.meal || record.note == nil || record.note == $0.0.note }
        if let note = record.note {
            let posible = relevantMeals.filter { $0.0.note?.hasPrefix(note) == true }
            if !posible.isEmpty {
                relevantMeals = posible
            }
        }
        let stricter = relevantMeals.filter { $0.0.meal == record.meal }
        if stricter.count > 3 {
            relevantMeals = stricter
        }
        return relevantMeals
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
        let predictedHigh = CGFloat(round(highs.sorted().median() + current.value))
        let predictedHigh25 = CGFloat(round(highs.sorted().percentile(0.15) + current.value))
        let predictedHigh75 = CGFloat(round(highs.sorted().percentile(0.85) + current.value))
        let predictedLow = CGFloat(round(lows.sorted().percentile(0.1) + current.value))
        let predictedLow50 = CGFloat(round(lows.sorted().median() + current.value))
        let predictedTime = record.date + timeToHigh.sorted().median()
        return Prediction(count: relevantMeals.count, mealTime: record.date, highDate: predictedTime, h10: predictedHigh25, h50: predictedHigh, h90: predictedHigh75, low50: predictedLow50, low: predictedLow)
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

extension SqliteDatabase {
    public func async(_ dbOp: @escaping () -> Void) {
        DispatchQueue.global().async {
            Storage.default.fileCoordinator.coordinate(writingItemAt: Storage.default.lockfile, options: [], error: nil, byAccessor: { (_) in
                dbOp()
            })
        }
    }

    public func sync(_ dbOp: @escaping () -> Void) {
        Storage.default.fileCoordinator.coordinate(writingItemAt: Storage.default.lockfile, options: [], error: nil, byAccessor: { (_) in
            dbOp()
        })
    }

}
