//
//  IntentHandler.swift
//  Intents
//
//  Created by Guy on 11/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Intents
import WoofKit
import Sqlable

private let sharedDbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "5h.sqlite"))

class IntentHandler: INExtension, CheckGlucoseIntentHandling {
    private let sharedDb: SqliteDatabase? = {
        let db = try? SqliteDatabase(filepath: sharedDbUrl.path)
        try! db?.createTable(GlucosePoint.self)
        return db
    }()
    private var coordinator: NSFileCoordinator!

    override init() {
        super.init()
        coordinator = NSFileCoordinator(filePresenter: self)
    }

    func handle(intent: CheckGlucoseIntent, completion: @escaping (CheckGlucoseIntentResponse) -> Void) {
        DispatchQueue.global().async {
            self.coordinator.coordinate(readingItemAt: sharedDbUrl, error: nil, byAccessor: { (_) in
                if let p = self.sharedDb?.evaluate(GlucosePoint.read().orderBy(GlucosePoint.date, .desc)), let current = p.first {
                    let value = Int(round(current.value))
                    let trend = (p[0].value - p[1].value) / (p[0].date - p[1].date) * 60
                    let trendPhrase: String = {
                        if trend > 2.8 {
                            return "rising fast"
                        } else if trend > 1.4 {
                            return "rising"
                        } else if trend > 0.5 {
                            return "moderately rising"
                        } else if trend > -0.5 {
                            return "stable"
                        } else if trend > -1.4 {
                            return "moderately dropping"
                        } else if trend > -2.8 {
                            return "dropping"
                        } else {
                            return "dropping fast"
                        }
                    }()
                    let time = Int(Date().timeIntervalSince(current.date) / 60)
                    let ago = time == 0 ? "less than a minute ago" : "\(time) minute\(time > 1 ? "s" : "") ago"
                    completion(CheckGlucoseIntentResponse.success(glucose: NSNumber(value: value), trend: trendPhrase, when: ago))
                } else {
                    completion(CheckGlucoseIntentResponse(code: .failure, userActivity: nil))
                }
            })
        }
    }
}

extension IntentHandler: NSFilePresenter {
    var presentedItemURL: URL? {
        return sharedDbUrl
    }

    var presentedItemOperationQueue: OperationQueue {
        return OperationQueue.main
    }
}