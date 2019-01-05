//
//  Extensions.swift
//  WoofWoof
//
//  Created by Guy on 21/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation
import UIKit
import Sqlable
private let hexDigits = "0123456789ABCDEF".map { $0 }

extension SqliteDatabase {
    @discardableResult func perform<T,R>(_ statement: @autoclosure () throws -> Statement<T,R>) throws -> R {
        return try statement().run(self)
    }

    @discardableResult func evaluate<T,R>(_ statement: @autoclosure () throws -> Statement<T,R>) -> R? {
        return try? statement().run(self)
    }
}

extension Collection where Element: SignedNumeric {
    func diff() -> [Element] {
        guard var last = first else { return [] }
        return dropFirst().reduce(into: []) {
            $0.append($1 - last)
            last = $1
        }
    }
}

extension UIColor {
    /**
     Create a ligher color
     */
    func lighter(by percentage: CGFloat = 30.0) -> UIColor {
        return self.adjustBrightness(by: abs(percentage))
    }

    /**
     Create a darker color
     */
    func darker(by percentage: CGFloat = 30.0) -> UIColor {
        return self.adjustBrightness(by: -abs(percentage))
    }

    /**
     Try to increase brightness or decrease saturation
     */
    func adjustBrightness(by percentage: CGFloat = 30.0) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if self.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            let newB = (1 + percentage / 100.0) * b
            if newB > 0 && newB < 1 {
                return UIColor(hue: h, saturation: s, brightness: newB, alpha: a)
            } else {
                let newS: CGFloat = min(max(s - (percentage/100.0)*s, 0.0), 1.0)
                return UIColor(hue: h, saturation: newS, brightness: b, alpha: a)
            }
        }
        return self
    }
}

extension Date {
    static private var compKey = false
    var components: DateComponents {
        if let comp = objc_getAssociatedObject(self, &Date.compKey) as? DateComponents {
            return comp
        } else {
            let comp = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond, .year, .month, .day], from: self)
            objc_setAssociatedObject(self, &Date.compKey, comp, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return comp
        }
    }
    var day: Int {
        return components.day ?? 0
    }
    var month: Int {
        return components.month ?? 0
    }
    var year: Int {
        return components.year ?? 0
    }
    var hour: Int {
        return components.hour ?? 0
    }
    var minute: Int {
        return components.minute ?? 0
    }
    var second: Int {
        return components.second ?? 0
    }
}

extension DateComponents {
    var date: Date {
        return Calendar.current.date(from: self) ?? Date(timeIntervalSince1970: 0)
    }
}


extension Data {
    public var hexString: String {
        return reduce(into: "") {
            $0.append(hexDigits[Int($1 / 16)])
            $0.append(hexDigits[Int($1 % 16)])
        }
    }
}

extension ArraySlice where Element == UInt8 {
    var uint16: UInt16 {
        return UInt16(self[0]) << 8 + UInt16(self[1])
    }
    func uint16(_ idx: Int) -> UInt16 {
        return UInt16(self[idx*2]) << 8 + UInt16(self[idx * 2 + 1])
    }
    var hexString: String {
        return reduce(into: "") {
            $0.append(hexDigits[Int($1 / 16)])
            $0.append(hexDigits[Int($1 % 16)])
        }
    }
}

extension Bundle {
    public static var documentsPath: String {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    }
}

extension Int {
    var s: TimeInterval {
        return TimeInterval(self)
    }
    var m: TimeInterval {
        return Double(self) * 60.0
    }
    var h: TimeInterval {
        return self.m * 60
    }
    var d: TimeInterval {
        return self.h * 24
    }
}




extension UIView {
    var width: CGFloat {
        return frame.width
    }
    var height: CGFloat {
        return frame.height
    }
}

func - (lhs:Date, rhs:Date) -> TimeInterval {
    return lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970
}

func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

extension CGPoint {
    func distance(to: CGPoint) -> CGFloat {
        return ((x - to.x) ** 2 + (y - to.y) ** 2) ** 0.5
    }
}


precedencegroup PowerPrecedence {
    higherThan: MultiplicationPrecedence
}

infix operator **: PowerPrecedence

func ** (lhs: CGFloat, rhs: CGFloat) -> CGFloat {
    return pow(lhs, rhs)
}

func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

func < (lhs: CGPoint, rhs: CGFloat) -> Bool {
    return abs(lhs.x) < rhs && abs(lhs.y) < rhs
}

public let defaults = UserDefaults.standard
extension UserDefaults {
    enum StringKey: String {
        case sensorSerial
    }
    enum DateKey: String {
        case lastStatisticsCalculation
        case lastLowBatteryNofication
    }
    enum DoubleKey: String {
        case additionalSlope
    }
    enum IntKey: String {
        case timeSpanIndex
        case watchWakeupTime
        case watchSleepTime
    }
    enum BoolKey: String {
        case didAlertCalibrateFirst12h
        case didAlertCalibrateSecond12h
        case didAlertCalibrateAfter24h
    }
    func register() {
        let defaults = [DoubleKey.additionalSlope.key: 1,
                        IntKey.watchWakeupTime.key: 5*60 + 15,
                        IntKey.watchSleepTime.key: 11*60]

        register(defaults: defaults)
    }
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
