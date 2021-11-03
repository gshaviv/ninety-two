//
//  GlucosePoint.swift
//  WoofWoof
//
//  Created by Guy on 22/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation
#if os(iOS)
import GRDB
#endif

public enum ReadingType {
    case history
    case calibration
    case trend
}

public protocol GlucoseReading {
    var date: Date { get }
    var value: Double { get }
    var type: ReadingType { get }
}

public struct GlucosePoint: GlucoseReading {
    public let date: Date
    public let value: Double
    public let type: ReadingType

    public init(date: Date, value: Double, isTrend: Bool = false) {
        self.date = date
        self.value = value
        self.type = isTrend ? .trend : .history
    }
}

#if os(iOS)
public protocol TablePersistable {
    static func createTable(in db: Database) throws
}
extension GlucosePoint: TableRecord, PersistableRecord, FetchableRecord, TablePersistable {
    public enum Column: String, ColumnExpression {
        case date
        case value
    }
    public static var databaseTableName = "BG"
    
    public static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column(Column.date.rawValue, .datetime)
            t.column(Column.value.rawValue, .double)
        }
    }
    
    public func encode(to container: inout PersistenceContainer) {
        container[Column.date] = date
        container[Column.value] = value
    }

    public init(row: Row)  {
        date = row[Column.date]
        value = row[Column.value]
        type = .history
    }
}
#endif

extension GlucosePoint: CustomStringConvertible {
    static private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .short
        df.timeZone = TimeZone.current
        return df
    }()

    public var description: String {
        return String(format: "<%@: %.1lf>", GlucosePoint.dateFormatter.string(from: date), value)
    }
}

extension GlucosePoint: Equatable {
}

#if os(iOS)


public struct Calibration: GlucoseReading {
    public var type: ReadingType {
        return .calibration
    }

    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

extension Calibration: TableRecord, PersistableRecord, FetchableRecord, TablePersistable {
    public enum Column: String, ColumnExpression {
        case date
        case value
    }
    public static var databaseTableName = "calibrations"
    
    public static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column(Column.date.rawValue, .datetime)
            t.column(Column.value.rawValue, .double)
        }
    }
    
    public func encode(to container: inout PersistenceContainer) {
        container[Column.date] = date
        container[Column.value] = value
    }
    
    public init(row: Row)  {
        date = row[Column.date]
        value = row[Column.value]
    }
}

#endif

public struct ManualMeasurement: GlucoseReading {
    public var type: ReadingType {
        .history
    }
    
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

#if os(iOS)
extension ManualMeasurement: TableRecord, PersistableRecord, FetchableRecord, TablePersistable {
    public enum Column: String, ColumnExpression {
        case date
        case value
    }
    public static var databaseTableName = "manual"
    
    static public func createTable(in db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column(Column.date.rawValue, .datetime)
            t.column(Column.value.rawValue, .double)
        }
    }
    
    public func encode(to container: inout PersistenceContainer) {
        container[Column.date] = date
        container[Column.value] = value
    }
    
    public init(row: Row)  {
        date = row[Column.date]
        value = row[Column.value]
    }
}

#endif

