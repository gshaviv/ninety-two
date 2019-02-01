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
    public var db: SqliteDatabase = {
        let dbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "read.sqlite"))
        let isNew = !FileManager.default.fileExists(atPath: dbUrl.path)
        let db = try! SqliteDatabase(filepath: dbUrl.path)
        db.queue = DispatchQueue(label: "db")
        try! db.createTable(GlucosePoint.self)
        try! db.createTable(Calibration.self)
        try! db.createTable(Record.self)
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
    public func relevantMeals(to record: Record) -> [Record] {
        let meals = allMeals.filter { abs(Double($0.bolus) + round($0.insulinOnBoardAtStart) - Double(record.bolus) - record.insulinOnBoardAtStart) < max(ceil(record.insulinOnBoardAtStart), ceil($0.insulinOnBoardAtStart), 1) && $0.id != record.id }
        var relevantMeals = meals.filter { $0.meal == record.meal || $0.note == record.note ?? "" }
        if let note = record.note {
            let posible = relevantMeals.filter { $0.note?.hasPrefix(note) == true }
            if !posible.isEmpty {
                relevantMeals = posible
            }
        }
        let stricter = relevantMeals.filter { $0.meal == record.meal }
        if stricter.count > 3 {
            relevantMeals = stricter
        }
        return relevantMeals
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
