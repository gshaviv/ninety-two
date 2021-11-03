//
//  Record.swift
//  WoofKit
//
//  Created by Guy on 21/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import GRDB
import Intents

public class Entry : Hashable, Equatable {
    public static func == (lhs: Entry, rhs: Entry) -> Bool {
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
    private var iobCalc: Calculation<Double>? = nil

    public required init(row: Row) {
        id = row[Column.id]
        type = MealType(rawValue: row[Column.type] ?? -1)
        bolus = row[Column.bolus]
        note = row[Column.note]
        carbs = row[Column.carbs]
        mealId = row[Column.mealId]
        date = row[Column.date]
        commonInit()
    }
}

extension Entry: TableRecord, PersistableRecord, FetchableRecord {
    public enum Column: String, ColumnExpression {
        case id, type, bolus, note, date, mealId, carbs
    }
    
    public static var databaseTableName: String = "entry"

   
    
    public func encode(to container: inout PersistenceContainer) {
        container[Column.id] = id
        container[Column.type] = type?.rawValue
        container[Column.bolus] = bolus
        container[Column.note] = note
        container[Column.mealId] = mealId
        container[Column.carbs] = carbs
        container[Column.date] = date
    }
   
    
}

extension Entry {

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

extension Entry {
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
    public var record: Entry {
        return Entry(date: Date.distantFuture, meal: Entry.MealType(name: meal), bolus: units?.intValue, note: note?.isEmpty == true ? nil : note)
    }
}
