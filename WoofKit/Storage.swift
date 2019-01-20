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
        try! db.createTable(Bolus.self)
        try! db.createTable(Meal.self)
        return db
    }()
    public let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    private(set) public var lastDay = Today()
    public func reloadToday() {
        lastDay = Today()
    }
}

public class Today {
    public lazy var boluses: [Bolus] = {
        let limit = Date() - 1.d
        return Storage.default.db.evaluate(Bolus.read().filter(Bolus.date > limit).orderBy(Bolus.date)) ?? []
    }()

    public lazy var meals: [Meal] = {
        let limit = Date() - 1.d
        return Storage.default.db.evaluate(Meal.read().filter(Bolus.date > limit).orderBy(Meal.date)) ?? []
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
