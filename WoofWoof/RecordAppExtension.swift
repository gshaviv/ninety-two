//
//  RecordAppExtension.swift
//  WoofWoof
//
//  Created by Guy on 16/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import WoofKit
import GRDB

extension Entry {
    var meal: Meal {
        guard let mealId = mealId else {
            return Meal(name: note)
        }
        return Storage.default.db.evaluate(Meal.filter(Meal.Column.id == mealId))?.last ?? Meal(name: note)
    }

    func discard() {
        if id == nil {
            return
        }
        try? Storage.default.db.write {
            try self.delete($0)
            if let mealid = mealId {
                try Meal.filter(Meal.Column.id == mealid).deleteAll($0)
            }
        }
        
    }
}

