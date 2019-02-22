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
            if record.isMeal && bolus == 0 && note == nil {
                completion(DiaryIntentResponse(code: .continueInApp, userActivity: nil))
            } else {
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

                    let blurb = possible[Int(arc4random_uniform(UInt32(possible.count)))]
                    if let prediction = Storage.default.prediction(for: record) {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .none
                        formatter.timeStyle = .short
                        if prediction.h90 > prediction.h10 && prediction.low50 > prediction.low {
                            let phrase = "\(blurb). Based on \(prediction.mealCount) previous similar meals, your glucose will be between \(Int(prediction.h10)) and \(Int(prediction.h90)) with an 80% chance, most likely will be \(Int(prediction.h50)) at \(formatter.string(from: prediction.highDate)). With a 90% it will stay above \(Int(prediction.low))."
                            completion(DiaryIntentResponse.success(phrase: phrase))
                        } else {
                            completion(DiaryIntentResponse.success(phrase: blurb))
                        }
                    } else {
                        completion(DiaryIntentResponse.success(phrase: blurb))
                    }
                }
            }
        }
    }
}


