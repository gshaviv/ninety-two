//
//  Meal.swift
//  WoofWoof
//
//  Created by Guy on 15/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import WoofKit
import Sqlable

public class FoodServing {
    public let foodId: Int
    public let amount: Double
    fileprivate(set) public var id: Int?
    fileprivate(set) public var mealId: Int?
    public lazy var food: Food = try! Food.with(id: self.foodId)

    public var carbs: Double {
        return amount / food.householdSize * food.serving * food.carbs / 100
    }

    public init(id: Int, amount: Double, mealId: Int? = nil) {
        self.foodId = id
        self.amount = amount
        self.mealId = mealId
    }

    public required init(row: ReadRow) throws {
        foodId = try row.get(FoodServing.foodId)
        amount = try row.get(FoodServing.amount)
        id = try row.get(FoodServing.id)
        mealId = try row.get(FoodServing.mealId)
    }
}

extension FoodServing: Sqlable {
    static let foodId = Column("ndb", .integer)
    static let amount = Column("serving", .real)
    static let id = Column("id", .integer, PrimaryKey(autoincrement: true))
    static let mealId = Column("mealId", .integer)

    public static var tableLayout = [id, mealId, foodId, amount]

    public func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case FoodServing.foodId:
            return foodId
        case FoodServing.amount:
            return amount
        case FoodServing.id:
            return id
        case FoodServing.mealId:
            return mealId
        default:
            return nil
        }
    }

    public func save() throws {
        if id == nil {
            id = Storage.default.db.evaluate(insert())
        } else {
            Storage.default.db.evaluate(update())
        }
    }
}

class Meal {
    private(set) var id: Int? {
        didSet {
            // debug
            assert(!(id != nil && oldValue != nil))
        }
    }
    var name: String?
    private(set) var servings: [FoodServing]

    init(name: String?) {
        self.name = name
        servings = []
        id = nil
    }

    var totalCarbs: Double {
        return servings.map { $0.carbs }.sum()
    }

    func append(_ serving: FoodServing) {
        serving.mealId = id
        servings.append(serving)
    }

    var servingCount: Int {
        return servings.count
    }

    func remove(servingAt idx: Int) {
        if servings[idx].id != nil {
            Storage.default.db.evaluate(servings[idx].delete())
        }
        servings.remove(at: idx)
    }

    subscript(index: Int) -> FoodServing {
        return servings[index]
    }

    required init(row: ReadRow) throws {
        id = try row.get(Meal.id)
        name = try row.get(Meal.name)
        servings = []
        if let s = try? FoodServing.read().filter(FoodServing.mealId == id!).run(Storage.default.db) {
            servings = s
        }
    }
    
    func reset() {
        id = nil
        for serving in servings {
            serving.mealId = nil
            serving.id = nil
        }
    }
}

extension Meal: Sqlable {
    static let id = Column("id", .integer, PrimaryKey(autoincrement: true))
    static let name = Column("name", .nullable(.text))
    static var tableLayout: [Column] = [id, name]

    func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case Meal.id:
            return id
        case Meal.name:
            return name
        default:
            return nil
        }
    }

    public func save() throws {
        if id == nil {
            id = Storage.default.db.evaluate(insert())
        } else {
            Storage.default.db.evaluate(update())
        }
        try servings.forEach {
            $0.mealId = self.id
            try $0.save()
        }
    }
}
