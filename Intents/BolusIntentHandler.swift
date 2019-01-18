//
//  BolusIntentHandler.swift
//  SiriIntents
//
//  Created by Guy on 18/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import Intents
import WoofKit
import Sqlable

class BolusHandler: NSObject, BolusIntentHandling {
    private  var lockfile: URL = {
        let url = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "lockfile"))
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "lock".write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }()
     var db: SqliteDatabase = {
        let dbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "read.sqlite"))
        let isNew = !FileManager.default.fileExists(atPath: dbUrl.path)
        let db = try! SqliteDatabase(filepath: dbUrl.path)
        db.queue = DispatchQueue(label: "db")
        try! db.createTable(GlucosePoint.self)
        try! db.createTable(Calibration.self)
        try! db.createTable(Bolus.self)
        return db
    }()
    private  var fileCoordinator = NSFileCoordinator(filePresenter: nil)
    func onDb(_ dbOp: @escaping () -> Void) {
        DispatchQueue.global().async {
            self.fileCoordinator.coordinate(writingItemAt: self.lockfile, options: [], error: nil, byAccessor: { (_) in
                dbOp()
            })
        }
    }
    func handle(intent: BolusIntent, completion: @escaping (BolusIntentResponse) -> Void) {
        if let u = intent.units {
            let b = Bolus(date: Date(), units: u.intValue)
            onDb {
                self.db.evaluate(b.insert())
                completion(BolusIntentResponse.success(units: u))
            }
            
        } else {
            completion(BolusIntentResponse(code: BolusIntentResponseCode.failureRequiringAppLaunch, userActivity: nil))
        }
    }

}
