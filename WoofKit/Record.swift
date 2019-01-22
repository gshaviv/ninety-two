//
//  Record.swift
//  WoofKit
//
//  Created by Guy on 21/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import Sqlable
import Intents

public struct Record {
    public let date: Date
    public enum Meal: Int {
        case breakfast
        case lunch
        case dinner
        case other

        public var name: String {
            switch self {
            case .breakfast:
                return "breakfast"

            case .lunch:
                return "lunch"

            case .dinner:
                return "dinner"

            case .other:
                return "o"
            }
        }

        public init(name: String) {
            switch name {
            case "breakfast":
                self = .breakfast

            case "lunch":
                self = .lunch

            case "dinner":
                self = .dinner

            default:
                self = .other
            }
        }
    }
    public var meal: Meal?
    public var bolus: Int?
    public private(set) var id: Int?
    public var note: String?

    public init(date: Date, meal: Meal? = nil, bolus: Int? = nil, note: String?) {
        self.date = date
        self.meal = meal
        self.bolus = bolus
        self.note = note
        self.id = nil
    }
}

extension Record: Sqlable {
    public static let id = Column("id", .integer, PrimaryKey(autoincrement: true))
    public static let meal = Column("meal", .nullable(.integer))
    public static let bolus = Column("bolus", .nullable(.integer))
    public static let note = Column("note", .nullable(.text))
    public static let date = Column("date", .date)
    public static var tableLayout = [id, meal, bolus, note, date]

    public func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case Record.id:
            return id

        case Record.meal:
            return meal?.rawValue

        case Record.bolus:
            return bolus

        case Record.note:
            return note

        case Record.date:
            return date

        default:
            return nil
        }
    }

    public init(row: ReadRow) throws {
        id = try row.get(Record.id)
        if let rv: Int = try row.get(Record.meal) {
            meal = Meal(rawValue: rv)
        }
        bolus = try row.get(Record.bolus)
        note = try row.get(Record.note)
        date = try row.get(Record.date)
    }

    public mutating func insert(to db:SqliteDatabase) {
        id = db.evaluate(insert())
    }

    public mutating func save(to db:SqliteDatabase) {
        if id == nil {
            insert(to: db)
        } else {
            db.evaluate(update())
        }
    }
}


extension Record {
    public enum IntentType {
        case meal
        case bolus
    }
    public func intent(type: IntentType) -> INIntent? {
        if let meal = meal, type == .meal {
            let m = MealIntent()
            m.type = meal.name
            switch meal {
            case .breakfast:
                m.suggestedInvocationPhrase = "I'm having breakfast"

            case .lunch:
                m.suggestedInvocationPhrase = "I'm having lunch"

            case .dinner:
                m.suggestedInvocationPhrase = "I'm having dinner"

            default:
                m.suggestedInvocationPhrase = "I'm eating"
            }
            return m
        } else if let b = bolus, type == .bolus {
            let intent = BolusIntent()
            intent.suggestedInvocationPhrase = "I took \(b) unit\(b > 1 ? "s" : "")"
            intent.units = NSNumber(value: b)
            return intent
        }
        return nil
    }
    public var isBolus: Bool {
        return bolus != nil
    }
    public var isMeal: Bool {
        return meal != nil
    }
}
