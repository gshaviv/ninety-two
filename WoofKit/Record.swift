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

public class Record : Hashable, Equatable {
    public static func == (lhs: Record, rhs: Record) -> Bool {
        return lhs.date == rhs.date && lhs.type == rhs.type && rhs.bolus == lhs.bolus && lhs.note == rhs.note
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(type)
        hasher.combine(note)
        hasher.combine(bolus)
    }

    public var date: Date

    public enum MealType: Int {
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

    public var type: MealType?
    public var bolus: Int
    private(set) public var id: Int?
    public var note: String?
    public var mealId: Int?
    public var carbs: Double = 0

    public init(id: Int? = nil, date: Date, meal: MealType? = nil, bolus: Int? = nil, note: String? = nil) {
        self.date = date
        self.type = meal
        self.bolus = bolus ?? 0
        self.note = note
        self.id = id
    
        commonInit()
    }

    private  func commonInit() {
        iobCalc = Calculation { [weak self] in
            guard let self = self else {
                return 0
            }
            let fromDate = self.date - (defaults[.diaMinutes] + defaults[.delayMinutes]) * 60
            return Storage.default.allEntries.filter { $0.date > fromDate && $0.date < self.date }.reduce(0.0) { $0 + $1.insulinAction(at: self.date).iob }
        }
    }
    private var iobCalc: Calculation<Double>?

    public required init(row: ReadRow) throws {
        id = try row.get(Record.id)
        if let rv: Int = try row.get(Record.type) {
            type = MealType(rawValue: rv)
        }
        bolus = try row.get(Record.bolus) ?? 0
        note = try row.get(Record.note)
        date = try row.get(Record.date)
        mealId = try row.get(Record.mealId)
        carbs = try row.get(Record.carbs) ?? 0
        commonInit()
    }
}

extension Record: Sqlable {
    public static let id = Column("id", .integer, PrimaryKey(autoincrement: true))
    public static let type = Column("meal", .nullable(.integer))
    public static let bolus = Column("bolus", .integer)
    public static let note = Column("note", .nullable(.text))
    public static let date = Column("date", .date)
    public static var mealId = Column("mealid", .integer)
    public static var carbs = Column("carbs", .real)
    public static var tableLayout = [id, type, bolus, note, date, mealId, carbs]

    public func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case Record.id:
            return id

        case Record.type:
            return type?.rawValue

        case Record.bolus:
            return bolus

        case Record.note:
            return note

        case Record.date:
            return date

        case Record.mealId:
            return mealId

        case Record.carbs:
            return carbs
            
        default:
            return nil
        }
    }

    public  func insert(to db: SqliteDatabase) {
        id = db.evaluate(insert())
    }

    public  func save(to db: SqliteDatabase) {
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
        return type != nil
    }
    public var intent: DiaryIntent {
        let foods = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: Bundle(for: Storage.self).path(forResource: "words", ofType: "json")!)), options: []) as! [String: [String]]

        var suggested: String = ""
        let intent = DiaryIntent()
        if let meal = type {
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
                suggested = notePhrase.isEmpty ? "I'm eating" : "I'm having \(notePhrase[0 ..< notePhrase.count - 5])"
            }
        } else if let n = note {
            let notePhrase: String
            let note = n.lowercased()
            intent.note = n
            if (n.components(separatedBy: " ").count == 1 && n.hasSuffix("s")) || n.components(separatedBy: " ").contains("And") {
                notePhrase = n
            } else {
                let x = note.rangeOfCharacter(from: CharacterSet(charactersIn: "aeoiu"))?.lowerBound == note.startIndex
                notePhrase = "\(x ? "an" : "a") \(self.note!)"
            }
            suggested = "I'm having \(notePhrase)"
        } else {
            intent.meal = "none"
            intent.note = ""
        }
        if isBolus {
            intent.units = NSNumber(value: bolus)
            if suggested.isEmpty {
                suggested = "I took "
            } else if type == nil {
                suggested += ", and I took "
            } else {
                suggested += ", with "
            }
            suggested += "\(bolus) units"
        } else {
            intent.units = NSNumber(value: 0)
        }

        intent.suggestedInvocationPhrase = suggested
        return intent
    }
}

extension Record {
    public func insulinAction(at date:Date) -> (activity: Double, iob: Double) {
        // based on: https://github.com/LoopKit/Loop/issues/388#issuecomment-317938473
        let t = (date - self.date) / 1.m - defaults[.delayMinutes]
        let td = defaults[.diaMinutes]
        let tp = defaults[.peakMinutes]
        if t < -defaults[.delayMinutes] || t > td || !isBolus {
            return (0,0)
        } else if t < 0 {
            return (0, Double(bolus))
        }

        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let a = 2 * tau / td
        let s = 1 / (1 - a + (1 + a) * exp(-td / tau))
        let activity = (s / tau ** 2) * t * (1 - t / td) * exp(-t / tau)
        let iob = 1 - s * (1 - a) * ((t ** 2 / (tau * td * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1)

        return (activity * Double(bolus),iob * Double(bolus))
    }

    public var insulinOnBoardAtStart: Double {
        return iobCalc!.value
    }
    
    public var cobOnStart: Double {
        let timeframe = (defaults[.diaMinutes] + defaults[.delayMinutes]) * 60
        let fromDate = self.date - timeframe
        return Storage.default.allEntries.filter { $0.date > fromDate && $0.date < self.date }.reduce(0.0) { $0 + $1.carbs * (1.0 - (self.date - $1.date) / timeframe) }
    }
}

extension DiaryIntent {
    public var record: Record {
        return Record(date: Date.distantFuture, meal: Record.MealType(name: meal), bolus: units?.intValue, note: note?.isEmpty == true ? nil : note)
    }
}
