//
//  WCKey.swift
//  WoofWoof
//
//  Created by Guy on 16/10/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation

enum WCKey: String {
    case measurements = "v"
    case trendValue = "t"
    case trendSymbol = "s"
    case sensorStart = "q"
    case complication = "c"
    case battery = "b"
    case events = "e"
    case summary = "u"
    case defaults = "f"
    case currentDate = "d"
}

func key(_ key: WCKey) -> String {
    key.rawValue
}

extension Dictionary where Key == WCKey {
    func withStringKeys() -> [String:Value] {
        reduce(into: [:]) { result, x in
            result[x.key.rawValue] = x.value
        }
    }
}

extension Dictionary where Key == String {
    func withWCKeys() -> [WCKey:Value] {
        reduce(into: [:]) { result, x in
            guard let k = WCKey(rawValue: x.key) else {
                return
            }
            result[k] = x.value
        }
    }
}
