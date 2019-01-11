//
//  UserDefaultsExtensions.swift
//  WoofWoof
//
//  Created by Guy on 05/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation

public let defaults = UserDefaults(suiteName: "group.com.tivstudio.woof")!

extension UserDefaults {

    enum StringKey: String {
        case sensorSerial
        case complicationState
    }

    enum DateKey: String {
        case lastStatisticsCalculation
        case lastLowBatteryNofication
        case lastEventAlertTime
    }

    enum DoubleKey: String {
        case additionalSlope
        case lowAlertLevel
        case highAlertLevel
        case minRange
        case maxRange
    }

    enum IntKey: String {
        case timeSpanIndex
        case watchWakeupTime
        case watchSleepTime
        case noSensorReadingCount
        case badDataCount
    }

    enum BoolKey: String {
        case didAlertCalibrateFirst12h
        case didAlertCalibrateSecond12h
        case didAlertCalibrateAfter24h
        case didAlertEvent
    }

    func register() {
        let defaults: [String: Any] = [DoubleKey.additionalSlope.key: 1,
                                     IntKey.watchWakeupTime.key: 5 * 60 + 15,
                                     IntKey.watchSleepTime.key: 23 * 60,
                                     DoubleKey.lowAlertLevel.key: 75.0,
                                     DoubleKey.highAlertLevel.key: 180.0,
                                     DoubleKey.minRange.key: 70.0,
                                     DoubleKey.maxRange.key: 180.0]

        register(defaults: defaults)
    }
}

extension UserDefaults {

    subscript(key: StringKey) -> String? {
        get {
            return object(forKey: key.rawValue) as? String
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }

    subscript(key: DateKey) -> Date? {
        get {
            return object(forKey: key.rawValue) as? Date
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }

    subscript(key: DoubleKey) -> Double {
        get {
            return double(forKey: key.rawValue)
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }

    subscript(key: IntKey) -> Int {
        get {
            return integer(forKey: key.rawValue)
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }

    subscript(key: BoolKey) -> Bool {
        get {
            return bool(forKey: key.rawValue)
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }
}

extension UserDefaults.StringKey {
    var key: String {
        return rawValue
    }
}

extension UserDefaults.DateKey {
    var key: String {
        return rawValue
    }
}

extension UserDefaults.DoubleKey {
    var key: String {
        return rawValue
    }
}

extension UserDefaults.IntKey {
    var key: String {
        return rawValue
    }
}

extension UserDefaults.BoolKey {
    var key: String {
        return rawValue
    }
}
