//
//  TrendSymbol.swift
//  WoofWoof
//
//  Created by Guy on 11/10/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation

public func trendSymbol(for trend: Double) -> String {
    if trend > 2.0 {
        return "⇈"
    } else if trend > 1.0 {
        return "↑"
    } else if trend > 0.33 {
        return "↗︎"
    } else if trend > -0.33 {
        return "→"
    } else if trend > -1.0 {
        return "↘︎"
    } else if trend > -2.0 {
        return "↓"
    } else {
        return "⇊"
    }
}
