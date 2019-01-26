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
        case nextCalibration
        case nextNoSensorAlert
    }

    public enum DoubleKey: String {
        case additionalSlope
        case lowAlertLevel
        case highAlertLevel
        case minRange
        case maxRange
        case level0, level1, level2, level3, level4
    }

    public enum IntKey: String {
        case timeSpanIndex
        case watchWakeupTime
        case watchSleepTime
        case badDataCount
    }

    public enum ColorKey: String {
        case color0
        case color1
        case color2
        case color3
        case color4, color5
    }

    public enum BoolKey: String {
        case didAlertEvent
    }

    public func register() {
        let defaults: [String: Any] = [DoubleKey.additionalSlope.key: 1,
                                       IntKey.watchWakeupTime.key: 5 * 60 + 15,
                                       IntKey.watchSleepTime.key: 23 * 60,
                                       DoubleKey.lowAlertLevel.key: 75.0,
                                       DoubleKey.highAlertLevel.key: 180.0,
                                       DoubleKey.minRange.key: 70.0,
                                       DoubleKey.maxRange.key: 180.0,
                                       ColorKey.color0.key: 0x00ff0000,
                                       DoubleKey.level0.key: 55.0,
                                       ColorKey.color1.key: 0x00ff4c4c,
                                       DoubleKey.level1.key: 70.0,
                                       ColorKey.color2.key: 0x0066ff66,
                                       DoubleKey.level2.key: 110.0,
                                       ColorKey.color3.key: 0x0000ff00,
                                       DoubleKey.level3.key: 140.0,
                                       ColorKey.color4.key: 0x007fff7f,
                                       DoubleKey.level4.key: 180.0,
                                       ColorKey.color5.key: 0x00ffff00,
                                       ]

        register(defaults: defaults)
    }
}

extension UserDefaults {
    public subscript(key: ColorKey) -> UIColor {
        get {
            return UIColor(rgb: UInt32(integer(forKey: key.rawValue)))
        }
        set {
            set(newValue.rgbValue, forKey: key.rawValue)
        }
    }
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

extension UserDefaults.ColorKey {
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
