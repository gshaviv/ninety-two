//
//  GlucosePoint.swift
//  WoofWoof
//
//  Created by Guy on 22/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation
import Sqlable

protocol GlucoseReading {
    var date: Date { get }
    var value: Double { get }
    var isCalibration: Bool { get }
}

struct GlucosePoint: GlucoseReading {
    var isCalibration: Bool {
        return false
    }

    let date: Date
    let value: Double
}

extension GlucosePoint: Sqlable {
    static let date = Column("date", .date)
    static let value = Column("value", .real)

    static var tableLayout = [date, value]

    func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case GlucosePoint.date:
            return date

        case GlucosePoint.value:
            return value

        default:
            return nil
        }
    }

    init(row: ReadRow) throws {
        date = try row.get(GlucosePoint.date)
        value = try row.get(GlucosePoint.value)
    }
}

extension GlucosePoint: CustomStringConvertible {
    static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .short
        df.timeZone = TimeZone.current
        return df
    }()

    var description: String {
        return String(format: "<%@: %.1lf>", GlucosePoint.dateFormatter.string(from: date), value)
    }
}

extension GlucosePoint: Equatable {

}

extension Measurement {
    var glucosePoint: GlucosePoint {
        return GlucosePoint(date: date, value: temperatureAlgorithmGlucose)
    }
}

struct Calibration: GlucoseReading {
    var isCalibration: Bool {
        return true
    }

    let date: Date
    let value: Double
}

extension Calibration: Sqlable {
    static let date = Column("date", .date)
    static let value = Column("value", .real)

    static var tableLayout = [date, value]

    func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case GlucosePoint.date:
            return date

        case GlucosePoint.value:
            return value

        default:
            return nil
        }
    }

    init(row: ReadRow) throws {
        date = try row.get(GlucosePoint.date)
        value = try row.get(GlucosePoint.value)
    }
}