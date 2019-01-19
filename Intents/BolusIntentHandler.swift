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
    func handle(intent: BolusIntent, completion: @escaping (BolusIntentResponse) -> Void) {
        if let u = intent.units {
            let b = Bolus(date: Date(), units: u.intValue)
            Storage.default.db.async {
                Storage.default.db.evaluate(b.insert())
                completion(BolusIntentResponse.success(units: u))
            }
            
        } else {
            completion(BolusIntentResponse(code: BolusIntentResponseCode.failureRequiringAppLaunch, userActivity: nil))
        }
    }
}

class MealHandler: NSObject, MealIntentHandling {
    func handle(intent: MealIntent, completion: @escaping (MealIntentResponse) -> Void) {
        let kind = Meal.Kind(name: intent.type ?? "other")
        let meal = Meal(date: Date(), kind: kind)
        Storage.default.db.async {
            Storage.default.db.evaluate(meal.insert())
            let possible = [
                "Bon apetit",
                "Enjoy!",
                "Yummy!",
                "I'm hungry",
                "Have fun",
                "Looks delicous",
                "Good for you",
                "Leave me something",
                "Can I join you?"
            ]
            completion(MealIntentResponse.success(response: possible[Int(arc4random_uniform(UInt32(possible.count)))]))
        }
    }
}
