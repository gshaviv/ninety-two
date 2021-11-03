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
import GRDB


class DiaryHandler: NSObject, DiaryIntentHandling {
    func handle(intent: DiaryIntent, completion: @escaping (DiaryIntentResponse) -> Void) {
        let kind: Entry.MealType?
        if let meal = Entry.MealType(name: intent.meal) {
            kind = meal
        } else {
            var count = Array<Int>(repeating: 0, count: 4)
            var diff = Array<TimeInterval>(repeating: 0, count: 4)
            Storage.default.allMeals.forEach {
                count[$0.type!.rawValue] += 1
                diff[$0.type!.rawValue] += abs(Date() - $0.date)
            }
            let ave = zip(count, diff).map { $0.1 / Double(max($0.0,1)) }.enumerated().reduce((0, 24.h)) {
                if $1.1 < $0.1 {
                    return $1
                } else {
                    return $0
                }
            }
            kind = Entry.MealType(rawValue: ave.0)
        }
        let note = intent.note?.isEmpty == true ? nil : intent.note
        let bolus = intent.units?.intValue ?? 0
        let when = Date().rounded
        let record = Storage.default.db.evaluate(Entry.filter(Entry.Column.date > Date() - 1.h))?.last ?? Entry(date: when)
            record.bolus = bolus
            record.type = kind
            record.note = note
            if record.isMeal && bolus == 0 && note == nil {
                completion(DiaryIntentResponse(code: .continueInApp, userActivity: nil))
            } else {
                try? Storage.default.db.write {
                    try record.save($0)
                }
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
                            let phrase = "\(blurb). Based on \(prediction.mealCount) previous similar meals, your glucose will be \(Int(prediction.h50)) and will stay above \(Int(prediction.low))."
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


