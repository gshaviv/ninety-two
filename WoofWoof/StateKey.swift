//
//  WCKey.swift
//  WoofWoof
//
//  Created by Guy on 16/10/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation

public enum StateKey: String {
    case change = "t"
    case symbol = "s"
    case sensorStart = "q"
    case complication = "c"
    case battery = "b"
    case events = "e"
    case summary = "u"
    case defaults = "f"
    case currentDate = "d"
    case history = "h"
    case trend = "r"
}

extension Dictionary where Key == StateKey {
    public func withStringKeys() -> [String:Value] {
        reduce(into: [:]) { result, x in
            result[x.key.rawValue] = x.value
        }
    }
}

extension Dictionary where Key == String {
    public func withStateKeys() -> [StateKey:Value] {
        reduce(into: [:]) { result, x in
            guard let k = StateKey(rawValue: x.key) else {
                return
            }
            result[k] = x.value
        }
    }
}
