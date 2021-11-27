//
//  IntentHandler.swift
//  Intents
//
//  Created by Guy on 11/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Intents
import WoofKit
import GRDB

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
    private var coordinator: NSFileCoordinator!

    override init() {
        super.init()
        coordinator = NSFileCoordinator(filePresenter: self)
    }

    func handle(intent: CheckGlucoseIntent, completion: @escaping (CheckGlucoseIntentResponse) -> Void) {
        DispatchQueue.global().async {
            let p = (try? Storage.default.trendDb.unsafeRead {
                try GlucosePoint.order(GlucosePoint.Column.date.desc).fetchAll($0)
            }) ?? []
            if let current = p.first {
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
        let minLeft = rint((horizon - Date()) / 1.m)
        if bobPhrase == "0" && minLeft < 5 {
            switch minLeft {
            case 0:
                completion(CheckBOBIntentResponse.little(end: "less than a minutes"))

            case 1:
                completion(CheckBOBIntentResponse.little(end: "1 minute"))

            default:
                completion(CheckBOBIntentResponse.little(end: "\(Int(minLeft)) minutes"))
            }
        } else {
            switch horizon - Date() {
            case ...15:
                let leftPhrase = "another \(Int(minLeft)) minutes"
                completion(CheckBOBIntentResponse.bobTime(bob: bobPhrase, end: leftPhrase))

            case ..<3.h:
                let whenPhrase = "until \(horizon.hour > 12 ? horizon.hour - 12 : horizon.hour):\(horizon.minute % "02ld")"
                completion(CheckBOBIntentResponse.bobTime(bob: bobPhrase, end: whenPhrase))

            default:
                completion(CheckBOBIntentResponse.success(bob: bobPhrase))
            }
        }
    }
}
