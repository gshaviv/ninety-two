//
//  SummaryInfo.swift
//  WoofWoof
//
//  Created by Guy on 30/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

struct Summary: Codable {
    let period: Int
    struct TimeInRange: Codable {
        let low: TimeInterval
        let inRange: TimeInterval
        let high: TimeInterval
    }
    let timeInRange: TimeInRange
    var totalTime: TimeInterval {
        timeInRange.low + timeInRange.inRange + timeInRange.high
    }
    var percentTimeIn: Decimal {
        100 - percentTimeAbove - percentTimeBelow
    }
    var percentTimeBelow: Decimal {
        (100 * timeInRange.low / max(totalTime,1)).decimal(digits: 1)
    }
    var percentTimeAbove: Decimal {
        (100 * timeInRange.high / max(totalTime,1)).decimal(digits: 1)
    }
    let maxLevel: Double
    let minLevel: Double
    let average: Double
    let a1c: Double
    struct Low: Codable {
        let count: Int
        let median: Int
    }
    let low: Low
    let atdd: Double
    let timeInLevel: [TimeInterval]
}

class SummaryInfo: ObservableObject {
    @Published var data: Summary
    public init(_ summary: Summary) {
        data = summary
    }
}
