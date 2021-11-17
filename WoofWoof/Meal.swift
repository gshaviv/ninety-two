//
//  Meal.swift
//  WoofWoof
//
//  Created by Guy on 15/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import WoofKit
import GRDB

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

    public required init(row: Row) {
        foodId = row[Column.foodId]
        amount = row[Column.amount]
        mealId = row[Column.mealId]
        id = row[Column.id]
    }
   
}

extension FoodServing: TableRecord, PersistableRecord, FetchableRecord, TablePersistable {
    enum Column: String, ColumnExpression {
        case foodId, amount, id, mealId
    }
    
    public static var databaseTableName = "servings"
    
    public static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, body: { t in
            t.autoIncrementedPrimaryKey(Column.id.rawValue)
            t.column(Column.foodId.rawValue, .integer)
                .notNull()
            t.column(Column.amount.rawValue, .double)
                .notNull()
            t.column(Column.mealId.rawValue, .integer)
                .notNull()
                .references(Meal.databaseTableName, onDelete: .cascade)
        })
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Column.foodId] = foodId
        container[Column.amount] = amount
        container[Column.id] = id
        container[Column.mealId] = mealId
    }

    public func save(_ db: Database) throws {
        if id == nil {
            try insert(db)
        } else {
            try update(db)
        }
    }
    
    public func didInsert(with rowID: Int64, for column: String?) {
        id = Int(rowID)
    }
}

class Meal {
    private(set) var id: Int?
    var name: String?
    private var _servings: [FoodServing]? = nil
    var servings: [FoodServing] {
        if let servings = _servings {
            return servings
        } else {
            do {
                if let id = id {
                    _servings = try Storage.default.db.read {
                        try FoodServing.filter(FoodServing.Column.mealId == id).fetchAll($0)
                    }
                    return _servings ?? []
                } else {
                    _servings = []
                    return []
                }
            } catch {
                return []
            }
        }
    }

    init(name: String?) {
        self.name = name
        id = nil
        _servings = []
    }
    
    var usedCount: Int {
        do {
            if let id = id {
                return try Storage.default.db.read {
                    try Entry.filter(Entry.Column.mealId == id).fetchCount($0)
                }
            } else {
                return 0
            }
        } catch {
            return 0
        }
    }

    var totalCarbs: Double {
        return servings.map { $0.carbs }.sum()
    }

    func append(_ serving: FoodServing) {
        serving.mealId = id
        serving.id = nil
        _servings?.append(serving)
    }

    var servingCount: Int {
        return servings.count
    }

    func remove(servingAt idx: Int) {
        if let sid = servings[idx].id  {
            do {
                _ = try Storage.default.db.write {
                    try FoodServing.deleteOne($0, key: sid)
                }
                _servings?.remove(at: idx)
            } catch {
                
            }
        } else {
            _servings?.remove(at: idx)
        }
    }

    subscript(index: Int) -> FoodServing {
        return servings[index]
    }

    public required init(row: Row)  {
        id = row[Meal.Column.id]
        name = row[Meal.Column.name]
    }
    
    func reset() {
        id = nil
        for serving in servings {
            serving.mealId = nil
            serving.id = nil
        }
    }
}

extension Meal: TableRecord, PersistableRecord, FetchableRecord, TablePersistable {
    func encode(to container: inout PersistenceContainer) {
        container[Column.id] = id
        container[Column.name] = name
    }
    
    static var databaseTableName = "meal"
    
    static public func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, body: { t in
            t.autoIncrementedPrimaryKey(Column.id.rawValue)
            t.column(Column.name.rawValue, .text)
        })
    }
    
    public enum Column: String, ColumnExpression {
        case id, name
    }
    
    public func save() throws {
        try Storage.default.db.write { db in
            if id == nil {
                try insert(db)
            } else {
                try update(db)
            }
            
            try servings.forEach {
                $0.mealId = self.id
                try $0.save(db)
            }
        }
    }
    
    func didInsert(with rowID: Int64, for column: String?) {
        id = Int(rowID)
    }
}

extension Meal: Hashable {
    static func == (lhs: Meal, rhs: Meal) -> Bool {
        if lhs.id != rhs.id {
            return false
        } else {
            return lhs.id != nil
        }
    }
    
    func hash(into hasher: inout Hasher) {
        if let id = id {
            hasher.combine(id)
        }
        for serving in servings {
            hasher.combine(serving.food.name)
            hasher.combine(serving.amount)
        }
    }
}

extension Entry: TablePersistable {
    static public func createTable(in db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.autoIncrementedPrimaryKey(Column.id.rawValue, onConflict: .replace)
            t.column(Column.type.rawValue, .integer)
            t.column(Column.bolus.rawValue, .integer)
                .defaults(to: 0)
            t.column(Column.note.rawValue, .text)
            t.column(Column.carbs.rawValue, .double)
                .defaults(to: 0)
            t.column(Column.mealId.rawValue, .integer)
                .references(Meal.databaseTableName, onDelete: .cascade)
            t.column(Column.date.rawValue, .datetime)
                .notNull()
        }
    }
}
