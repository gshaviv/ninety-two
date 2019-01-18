//
//  Bolus.swift
//  WoofKit
//
//  Created by Guy on 17/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import Sqlable

public struct Bolus {
    public let date: Date
    public let units: Int

    public init(date: Date, units: Int) {
        self.date = date
        self.units = units
    }
}

extension Bolus: Sqlable {
    public static let date = Column("date", .date)
    public static let units = Column("units", .integer)
    public static var tableLayout: [Column] = [date, units]

    public func valueForColumn(_ column: Column) -> SqlValue? {
        switch column {
        case Bolus.date:
            return date

        case Bolus.units:
            return units

        default:
            return nil
        }
    }

    public init(row: ReadRow) throws {
        date = try row.get(Bolus.date)
        units = try row.get(Bolus.units)
    }


}
