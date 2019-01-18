//
//  Meal.swift
//  WoofKit
//
//  Created by Guy on 18/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import Sqlable

public struct Meal {
    public enum Kind: Int {
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
    }
    public let kind: Kind
    public let date: Date

    public init(date: Date, kind: Kind) {
        self.date = date
        self.kind = kind
    }
}

extension Meal: Sqlable {
    public static let kind = Column("kind", .integer)
    public static let date = Column("date", .date)
    public static let tableLayout = [date,kind]

    public func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case Meal.kind:
            return kind.rawValue

        case Meal.date:
            return date

        default:
            return nil
        }
    }

    public init(row: ReadRow) throws {
        date = try row.get(Meal.date)
        kind = Kind(rawValue: try row.get(Meal.kind)) ?? .other
    }
}

extension Meal {
    public var intent: MealIntent {
        let m = MealIntent()
        m.type = MealType(rawValue: kind.rawValue + 1) ?? .other
        switch kind {
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
    }
}
