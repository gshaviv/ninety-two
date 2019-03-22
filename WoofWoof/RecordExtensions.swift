//
//  RecordExtensions.swift
//  WoofWoof
//
//  Created by Guy on 22/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import WoofKit
import Sqlable

extension Record {
    public func discard() {
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
    fileprivate func discard(db: SqliteDatabase) {
        for serving in servings {
            db.evaluate(serving.delete())
        }
        db.evaluate(self.delete())
    }
}
