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

class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any? {
        switch intent {
        case is CheckGlucoseIntent:
            return CheckIntentHandler()

        case is DiaryIntent:
            return DiaryHandler()

        case is CheckBOBIntent:
            return CheckBOBHandler()

        default:
            return nil
        }
    }
}

class CheckIntentHandler: NSObject, CheckGlucoseIntentHandling {
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

extension CheckIntentHandler: NSFilePresenter {
    var presentedItemURL: URL? {
        return sharedDbUrl
    }

    var presentedItemOperationQueue: OperationQueue {
        return OperationQueue.main
    }
}


class CheckBOBHandler: NSObject, CheckBOBIntentHandling {
    func handle(intent: CheckBOBIntent, completion: @escaping (CheckBOBIntentResponse) -> Void) {
        let bob = Storage.default.insulinOnBoard(at: Date())
        guard let horizon = Storage.default.insulinHorizon() else {
            completion(CheckBOBIntentResponse(code: .none, userActivity: nil))
            return
        }
        var bobPhrase = bob % ".1lf"
        if bobPhrase.hasSuffix(".0") {
            bobPhrase = bobPhrase[0 ..< (bobPhrase.count - 2)]
        }
        if bobPhrase == "0" {
            let minLeft = rint((horizon - Date()) / 1.m)
            switch minLeft {
            case 0:
                completion(CheckBOBIntentResponse.little(end: "less than a minutes"))

            case 1:
                completion(CheckBOBIntentResponse.little(end: "1 minute"))

            default:
                completion(CheckBOBIntentResponse.little(end: "\(Int(minLeft)) minutes"))
            }
        } else {
            if horizon - Date() < 30.m {
                let minLeft = "another \(Int(rint((horizon - Date()) / 1.m))) minutes"
                completion(CheckBOBIntentResponse.bobTime(bob: bobPhrase, end: minLeft))
            } else if horizon - Date() < 2.h {
                let whenPhrase = "until \(horizon.hour > 12 ? horizon.hour - 12 : horizon.hour):\(horizon.minute)"
                completion(CheckBOBIntentResponse.bobTime(bob: bobPhrase, end: whenPhrase))
            } else {
                completion(CheckBOBIntentResponse.success(bob: bobPhrase))
            }
        }
    }
}
