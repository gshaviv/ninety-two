//
//  GlucosePoint.swift
//  WoofWoof
//
//  Created by Guy on 22/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation
#if os(iOS)
import Sqlable
#endif

public protocol GlucoseReading {
    var date: Date { get }
    var value: Double { get }
    var isCalibration: Bool { get }
    var isTrend: Bool { get }
}

extension GlucoseReading {
    public var isCalibration: Bool {
        return false
    }
}

public struct GlucosePoint: GlucoseReading {
    public let date: Date
    public let value: Double
    public let isTrend: Bool

    public init(date: Date, value: Double, isTrend: Bool = false) {
        self.date = date
        self.value = value
        self.isTrend = isTrend
    }
}

#if os(iOS)
extension GlucosePoint: Sqlable {
    public static let date = Column("date", .date)
    public static let value = Column("value", .real)

    public static var tableLayout = [date, value]

    public func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case GlucosePoint.date:
            return date

        case GlucosePoint.value:
            return value

        default:
            return nil
        }
    }

    public init(row: ReadRow) throws {
        date = try row.get(GlucosePoint.date)
        value = try row.get(GlucosePoint.value)
        isTrend = false
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
    public var isTrend: Bool {
        return false
    }
    
    public var isCalibration: Bool {
        return true
    }

    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

extension Calibration: Sqlable {
    public static let date = Column("date", .date, PrimaryKey(autoincrement: false))
    public static let value = Column("value", .real)

    public static var tableLayout = [date, value]

    public func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case Calibration.date:
            return date

        case Calibration.value:
            return value

        default:
            return nil
        }
    }

    public init(row: ReadRow) throws {
        date = try row.get(GlucosePoint.date)
        value = try row.get(GlucosePoint.value)
    }
}
#endif

public struct ManualMeasurement: GlucoseReading {
    public var isTrend: Bool {
        return false
    }
    
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

#if os(iOS)
extension ManualMeasurement: Sqlable {
    public static let date = Column("date", .date, PrimaryKey(autoincrement: false))
    public static let value = Column("value", .real)

    public static var tableLayout = [date, value]

    public func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case ManualMeasurement.date:
            return date

        case ManualMeasurement.value:
            return value

        default:
            return nil
        }
    }

    public init(row: ReadRow) throws {
        date = try row.get(GlucosePoint.date)
        value = try row.get(GlucosePoint.value)
    }
}
#endif

