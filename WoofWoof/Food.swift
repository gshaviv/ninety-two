//
//  Food.swift
//  WoofWoof
//
//  Created by Guy on 15/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import GRDB
import WoofKit

private let fooDB: DatabasePool = {
    let path = Bundle.main.path(forResource: "foo", ofType: "db")!
    let url = URL(fileURLWithPath: path)
    return try! Storage.openReadOnlyDatabase(at: url)!
}()

public enum FoodError: Error {
    case noSuchFood
}
public struct Food {
    public let name: String
    public let manufacturer: String?
    public let ingredients: String?
    public let id: Int
    public let serving: Double
    public let householdSize: Double
    public let householdName: String
    public let carbs: Double

    public static func with(id: Int)  throws -> Food {
        if let food = try fooDB.perform(Food.filter(Food.Column.id == id)).first {
            return food
        }
        throw FoodError.noSuchFood
    }

    public static func matching(term: String) -> [Food]? {
        if term.hasPrefix("!") {
            return fooDB.evaluate(Food.filter(!Food.Column.name.like("%\(term[1...])%")))
        } else {
            return fooDB.evaluate(Food.filter(Food.Column.name.like("%\(term)%")))
        }
    }
    
    
}

extension Food: FetchableRecord, TableRecord {
    enum Column: String, ColumnExpression {
        case id = "ndb"
        case name
        case ingredients
        case manufacturer = "man"
        case serving
        case householdSize = "household_size"
        case householdName = "household_uom"
        case carbs
    }
   
    public init(row: Row) {
        id = row[Column.id]
        manufacturer = row[Column.manufacturer]
        ingredients = row[Column.ingredients]
        name = row[Column.name]
        serving = row[Column.serving]
        householdSize = row[Column.householdSize]
        householdName = row[Column.householdName]
        let readCarbs: Double? = row[Column.carbs]
        carbs = readCarbs ?? 0
    }

    public static var databaseTableName: String = "food"
}
