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
    }
    public func relevantMeals(to record: Record, iob: Double = 0) -> [Record] {
        let meals = db.evaluate(Record.read().filter(Record.meal != Null() && Record.bolus >= record.bolus && Record.bolus <= record.bolus + Int(round(iob)) && Record.date < record.date).orderBy(Record.date)) ?? []
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
        let records = db.evaluate(Record.read().filter(Record.bolus > 0 && Record.date > date - dia)) ?? []
        if records.isEmpty {
            return 0
        }
        return records.reduce(0) { $0 + $1.insulinAction(at: date).iob }
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
