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
import UserNotifications
private let hexDigits = "0123456789ABCDEF".map { $0 }

extension SqliteDatabase {

    @discardableResult func perform<T, R>(_ statement: @autoclosure () throws -> Statement<T, R>) throws -> R {
        return try statement().run(self)
    }

    @discardableResult func evaluate<T, R>(_ statement: @autoclosure () throws -> Statement<T, R>) -> R? {
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
                let newS: CGFloat = min(max(s - (percentage / 100.0) * s, 0.0), 1.0)
                return UIColor(hue: h, saturation: newS, brightness: b, alpha: a)
            }
        }
        return self
    }
}

extension Date {
    private static var compKey = false
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
        return UInt16(self[idx * 2]) << 8 + UInt16(self[idx * 2 + 1])
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

func - (lhs: Date, rhs: Date) -> TimeInterval {
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

extension UNNotificationSound {
    static let calibrationNeeded = UNNotificationSoundName(rawValue: "Siri_Calibration_Needed.caf")
    static let lowGlucose = UNNotificationSoundName(rawValue: "Siri_Low_Glucose.caf")
    static let highGlucose = UNNotificationSoundName(rawValue: "Siri_High_Glucose.caf")
    static let missed = UNNotificationSoundName(rawValue: "Siri_Missed_Readings.caf")
}

public extension DispatchQueue {
    public func after(withDelay delay: Double, closure: @escaping (() -> Void)) {
        let dispatchTime: DispatchTime = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        asyncAfter(deadline: dispatchTime, execute: closure)
    }
}

public extension String {
    /// Trimming string whitespace
    public var trimmed: String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns string's path extension. Like NSString but Swift
    public var pathExtension: String {
        if let idx = self.range(of: ".", options: .backwards, range: self.startIndex ..< self.endIndex, locale: nil)?.upperBound {
            return String(self[idx...])
        }
        return ""
    }

    /// Returns string's last path component. Like NSString but Swift
    public var lastPathComponent: String {
        if let idx = self.range(of: "/", options: .backwards, range: self.startIndex ..< self.endIndex, locale: nil)?.upperBound {
            return String(self[idx...])
        }
        return self
    }

    /// Delete last path component, like NSString, but swift, return without the trailing /
    public var deletingLastPathComponent: String {
        if let idx = self.range(of: "/", options: .backwards, range: self.startIndex ..< self.endIndex, locale: nil)?.lowerBound {
            return String(self[..<idx])
        }
        return ""
    }

    /// Add path components, like NSString but swift
    public func appending(pathComponent str: String) -> String {
        return hasSuffix("/") || str.hasPrefix("/") ? "\(self)\(str)" : "\(self)/\(str)"
    }

    public mutating func append(pathComponent str: String) {
        if !hasSuffix("/") && !str.hasPrefix("/") {
            append("/")
        }
        append(str)
    }

    /// add path extension
    public func appending(pathExtension ext: String) -> String {
        return hasSuffix(".") || ext.hasPrefix(".") ? "\(self)\(ext)" : "\(self).\(ext)"
    }

    public mutating func append(pathExtension ext: String) {
        if !hasSuffix(".") && !ext.hasPrefix(".") {
            append(".")
        }
        append(ext)
    }

    /// Delete path extension
    public var deletingPathExtension: String {
        if let idx = self.range(of: ".", options: .backwards, range: self.startIndex ..< self.endIndex, locale: nil)?.lowerBound {
            return String(self[..<idx])
        }
        return self
    }

    /// Convenience method so optionals can be used.. e.g. myString?.toInt()
    public func toInt() -> Int? {
        return Int(self)
    }
}
