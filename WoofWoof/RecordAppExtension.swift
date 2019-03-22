//
//  RecordAppExtension.swift
//  WoofWoof
//
//  Created by Guy on 16/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import WoofKit
import Sqlable

extension Record {
    var meal: Meal {
        guard let mealId = mealId else {
            return Meal(name: note)
        }
        return Storage.default.db.evaluate(Meal.read().filter(Meal.id == mealId))?.last ?? Meal(name: note)
    }

    func discard() {
        if id == nil {
            return
        }
        try? Storage.default.db.transaction { (db)  in
            db.evaluate(self.delete())
            if let mealId = mealId {
                if let records = Storage.default.db.evaluate(Record.read().filter(Record.mealId == mealId)), records.isEmpty {
                    meal.discard(db: db)
                }
            }
        }
    }
}

extension Meal {
    func discard(db: SqliteDatabase) {
        for serving in servings {
            db.evaluate(serving.delete())
        }
        db.evaluate(self.delete())
    }
}
