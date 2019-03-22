//
//  Food.swift
//  WoofWoof
//
//  Created by Guy on 15/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import Sqlable
import WoofKit

private let fooDB = try! SqliteDatabase(filepath: Bundle.main.path(forResource: "foo", ofType: "db")!, readOnly: true)

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
        if let food = try fooDB.perform(Food.read().filter(Food.id == id)).first {
            return food
        }
        throw FoodError.noSuchFood
    }

    public static func matching(term: String) -> [Food]? {
        if term.hasPrefix("!") {
            return fooDB.evaluate(Food.read().filter(!Food.name.like("%\(term[1...])%")))
        } else {
            return fooDB.evaluate(Food.read().filter(Food.name.like("%\(term)%")))
        }
    }
}

extension Food: Sqlable {
    public static let id = Column("ndb", .integer)
    public static let name = Column("name", .text)
    public static let ingredients = Column("ingredients", .nullable(.text))
    public static let manufacturer = Column("man", .nullable((.text)))
    public static let serving = Column("serving", .real)
    public static let householdSize = Column("household_size", .real)
    public static let householdName = Column("household_uom", .text)
    public static let carbs = Column("carbs", .real)

    public init(row: ReadRow) throws {
        id = try row.get(Food.id)
        manufacturer = try row.get(Food.manufacturer)
        ingredients = try row.get(Food.ingredients)
        name = try row.get(Food.name)
        serving = try row.get(Food.serving)
        householdSize = try row.get(Food.householdSize)
        householdName = try row.get(Food.householdName)
        carbs = try row.get(Food.carbs)
    }

    public static var tableLayout: [Column] = [id, name, manufacturer, ingredients, serving, householdSize, householdName, carbs]
    public static var tableName = "food"

    public func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case Food.id:
            return id

        case Food.name:
            return name

        case Food.manufacturer:
            return manufacturer

        case Food.ingredients:
            return ingredients

        case Food.serving:
            return serving

        case Food.householdSize:
            return householdSize

        case Food.householdName:
            return householdName

        case Food.carbs:
            return carbs

        default:
            return nil
        }
    }


}
