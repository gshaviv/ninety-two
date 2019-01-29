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
    public var date: Date

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
                return "other"
            }
        }

        public init?(name: String?) {
            guard let name = name else {
                return nil
            }
            switch name {
            case "breakfast":
                self = .breakfast

            case "lunch":
                self = .lunch

            case "dinner":
                self = .dinner

            case "other":
                self = .other

            default:
                return nil
            }
        }
    }

    public var meal: Meal?
    public var bolus: Int
    private(set) public var id: Int?
    public var note: String?

    public init(date: Date, meal: Meal? = nil, bolus: Int? = nil, note: String? = nil) {
        self.date = date
        self.meal = meal
        self.bolus = bolus ?? 0
        self.note = note
        self.id = nil
    }
}

extension Record: Sqlable {
    public static let id = Column("id", .integer, PrimaryKey(autoincrement: true))
    public static let meal = Column("meal", .nullable(.integer))
    public static let bolus = Column("bolus", .integer)
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
        bolus = try row.get(Record.bolus) ?? 0
        note = try row.get(Record.note)
        date = try row.get(Record.date)
    }

    public mutating func insert(to db: SqliteDatabase) {
        id = db.evaluate(insert())
    }

    public mutating func save(to db: SqliteDatabase) {
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

    public var isBolus: Bool {
        return bolus > 0
    }
    public var isMeal: Bool {
        return meal != nil
    }
    public var intent: DiaryIntent {
        let foods = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: Bundle(for: Storage.self).path(forResource: "words", ofType: "json")!)), options: []) as! [String: [String]]

        var suggested: String = ""
        let intent = DiaryIntent()
        if let meal = meal {
            let notePhrase: String
            if let note = note?.lowercased() {
                intent.note = self.note
                if (foods["fruit"] ?? foods["vegetables"] ?? foods["dishes"])?.contains(note) == true {
                    let x = note.rangeOfCharacter(from: CharacterSet(charactersIn: "aeoiu"))?.lowerBound == note.startIndex
                    notePhrase = "\(x ? "an" : "a") \(self.note!) for "
                } else {
                    notePhrase = "\(note) for "
                }
            } else {
                intent.note = ""
                notePhrase = ""
            }
            intent.meal = meal.name
            switch meal {
            case .breakfast:
                suggested = "I'm having \(notePhrase)breakfast"

            case .lunch:
                suggested = "I'm having \(notePhrase)lunch"

            case .dinner:
                suggested = "I'm having \(notePhrase)dinner"

            default:
                suggested = notePhrase.isEmpty ? "I'm eating" : "I'm eating \(notePhrase[0 ..< notePhrase.count - 5])"
            }
        } else {
            intent.meal = "none"
            intent.note = ""
        }
        if isBolus {
            intent.units = NSNumber(value: bolus)
            if suggested.isEmpty {
                suggested = "I "
            } else {
                suggested += ", and I "
            }
            suggested += "took \(bolus) units"
        } else {
            intent.units = NSNumber(value: 0)
        }

        intent.suggestedInvocationPhrase = suggested
        return intent
    }
}

extension Record {
    public func insulinAction(at date:Date) -> (activity: Double, iob: Double) {
        let t = (date - self.date) / 1.m
        let td = defaults[.diaMinutes]
        let tp = defaults[.peakMinutes]
        if t < 0 || t > td || !isBolus {
            return (0,0)
        }

        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let a = 2 * tau / td
        let s = 1 / (1 - a + (1 + a) * exp(-td / tau))
        let activity = (s / tau ** 2) * t * (1 - t / td) * exp(-t / tau)
        let iob = 1 - s * (1 - a) * ((t ** 2 / (tau * td * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1)

        return (activity * Double(bolus),iob * Double(bolus))
    }
}
