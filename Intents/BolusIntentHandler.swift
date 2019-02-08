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
        if comp.minute ?? 0 > 59 {
            comp.hour = (comp.hour ?? 0) + 1
        }
        comp.minute = Int(round(Double(comp.minute ?? 0)))
        return comp.toDate()
    }
}

class DiaryHandler: NSObject, DiaryIntentHandling {
    func handle(intent: DiaryIntent, completion: @escaping (DiaryIntentResponse) -> Void) {
        let kind = Record.Meal(name: intent.meal)
        let note = intent.note?.isEmpty == true ? nil : intent.note
        let bolus = intent.units?.intValue ?? 0
        let when = Date().rounded
        Storage.default.db.async {
            let record = Storage.default.db.evaluate(Record.read().filter(Record.date > Date() - 1.h))?.last ?? Record(date: when)
            record.bolus = bolus
            record.meal = kind
            record.note = note
            record.save(to: Storage.default.db)
            if !record.isMeal, let units = intent.units {
                completion(DiaryIntentResponse.bolus(units: units))
            } else {
                let possible = [
                    "Bon appetit",
                    "Enjoy!",
                    "Yummy!",
                    "I'm hungry too",
                    "Have fun",
                    "Looks delicious",
                    "Good for you",
                    "Leave me something",
                    "Can I join you?",
                    "I want that too",
                    "No one ever gives me anything to eat"
                ]
                completion(DiaryIntentResponse.success(phrase: possible[Int(arc4random_uniform(UInt32(possible.count)))]))
            }
        }
    }
}


