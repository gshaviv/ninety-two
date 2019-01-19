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

    public enum StringKey: String {
        case sensorSerial
        case complicationState
    }

    public enum DateKey: String {
        case lastStatisticsCalculation
        case lastLowBatteryNofication
        case lastEventAlertTime
    }

    public enum DoubleKey: String {
        case additionalSlope
        case lowAlertLevel
        case highAlertLevel
        case minRange
        case maxRange
    }

    public enum IntKey: String {
        case timeSpanIndex
        case watchWakeupTime
        case watchSleepTime
        case noSensorReadingCount
        case badDataCount
    }

    public enum BoolKey: String {
        case didAlertCalibrateFirst12h
        case didAlertCalibrateSecond12h
        case didAlertCalibrateAfter24h
        case didAlertEvent
        case didAskAddLunchToSiri
        case didAskAddBreakfastToSiri
        case didAskAddDinnerToSiri
        case didAskAddOtherToSiri
    }

    public func register() {
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

    public subscript(key: StringKey) -> String? {
        get {
            return object(forKey: key.rawValue) as? String
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }

    public subscript(key: DateKey) -> Date? {
        get {
            return object(forKey: key.rawValue) as? Date
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }

    public subscript(key: DoubleKey) -> Double {
        get {
            return double(forKey: key.rawValue)
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }

    public subscript(key: IntKey) -> Int {
        get {
            return integer(forKey: key.rawValue)
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }

    public subscript(key: BoolKey) -> Bool {
        get {
            return bool(forKey: key.rawValue)
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }
}

extension UserDefaults.StringKey {
    fileprivate var key: String {
        return rawValue
    }
}

extension UserDefaults.DateKey {
    fileprivate var key: String {
        return rawValue
    }
}

extension UserDefaults.DoubleKey {
    fileprivate var key: String {
        return rawValue
    }
}

extension UserDefaults.IntKey {
    fileprivate var key: String {
        return rawValue
    }
}

extension UserDefaults.BoolKey {
    fileprivate var key: String {
        return rawValue
    }
}
