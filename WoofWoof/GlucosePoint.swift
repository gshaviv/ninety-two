//
//  GlucosePoint.swift
//  WoofWoof
//
//  Created by Guy on 22/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation
import Sqlable

struct GlocusePoint {
    let date: Date
    let value: Double
}

extension GlocusePoint: Sqlable {
    static let date = Column("date", .date)
    static let value = Column("value", .real)

    static var tableLayout = [date, value]

    func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case GlocusePoint.date:
            return date

        case GlocusePoint.value:
            return value

        default:
            return nil
        }
    }

    init(row: ReadRow) throws {
        date = try row.get(GlocusePoint.date)
        value = try row.get(GlocusePoint.value)
    }
}

extension GlocusePoint: CustomStringConvertible {
    static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .long
        df.dateStyle = .medium
        df.timeZone = TimeZone.current
        return df
    }()

    var description: String {
        return String(format: "<%@: %.1lf>", GlocusePoint.dateFormatter.string(from: date), value)
    }
}

extension GlocusePoint: Equatable {

}

extension Measurement {
    var glucosePoint: GlocusePoint {
        return GlocusePoint(date: date, value: temperatureAlgorithmGlucose)
    }
}



// zcode fingerprint = 5c5cf8358f02ee38ab296f630204397b
