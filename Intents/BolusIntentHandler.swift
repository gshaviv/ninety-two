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

extension Date {
    var rounded: Date {
        var comp = components
        if comp.minute ?? 0 > 57 {
            comp.hour = (comp.hour ?? 0) + 1
        }
        comp.minute = Int(round(Double(comp.minute ?? 0) / 5.0) * 5)
        return comp.toDate()
    }
}

class BolusHandler: NSObject, BolusIntentHandling {
    func handle(intent: BolusIntent, completion: @escaping (BolusIntentResponse) -> Void) {
        if let u = intent.units, let n = intent.units?.intValue, n > 0 {
            Storage.default.db.async {
                let when = Date().rounded
                var record = Storage.default.db.evaluate(Record.read().filter(Record.date > Date() - 1.h))?.last ?? Record(date: when, note: nil)
                record.bolus = n
                record.save(to: Storage.default.db)
                completion(BolusIntentResponse.success(units: u))
            }
            
        } else {
            completion(BolusIntentResponse(code: BolusIntentResponseCode.failureRequiringAppLaunch, userActivity: nil))
        }
    }
}

class MealHandler: NSObject, MealIntentHandling {
    func handle(intent: MealIntent, completion: @escaping (MealIntentResponse) -> Void) {
        let kind = Record.Meal(name: intent.type ?? "other")
        Storage.default.db.async {
            let when = Date().rounded
            var record = Storage.default.db.evaluate(Record.read().filter(Record.date > Date() - 1.h))?.last ?? Record(date: when, note: nil)
            record.meal = kind
            record.save(to: Storage.default.db)
            let possible = [
                "Bon appetit",
                "Enjoy!",
                "Yummy!",
                "I'm hungry",
                "Have fun",
                "Looks delicious",
                "Good for you",
                "Leave me something",
                "Can I join you?"
            ]
            completion(MealIntentResponse.success(response: possible[Int(arc4random_uniform(UInt32(possible.count)))]))
        }
    }
}
