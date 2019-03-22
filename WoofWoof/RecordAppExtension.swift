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
}
