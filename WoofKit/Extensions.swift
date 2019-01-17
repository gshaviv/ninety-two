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

extension String {
    public subscript(index: Int) -> String {
        get {
            return String(self[self.index(self.startIndex, offsetBy: index)])
        }
        set {
            self[index ..< index + 1] = newValue
        }
    }

    public subscript(integerRange: Range<Int>) -> String {
        get {
            let start = index(startIndex, offsetBy: integerRange.lowerBound)
            let end = index(startIndex, offsetBy: integerRange.upperBound)
            return String(self[start ..< end])
        }
        set {
            let start = index(startIndex, offsetBy: integerRange.lowerBound)
            let end = index(startIndex, offsetBy: integerRange.upperBound)
            replaceSubrange(start ..< end, with: newValue)
        }
    }

    public subscript(from: CountablePartialRangeFrom<Int>) -> String {
        get {
            let start = index(startIndex, offsetBy: from.lowerBound)
            return String(self[start ..< endIndex])
        }
        set {
            let start = index(startIndex, offsetBy: from.lowerBound)
            replaceSubrange(start ..< endIndex, with: newValue)
        }
    }

    public subscript(upTo: PartialRangeUpTo<Int>) -> String {
        get {
            guard let upper = index(startIndex, offsetBy: upTo.upperBound, limitedBy: endIndex) else {
                return ""
            }
            return String(self[startIndex ..< upper])
        }
        set {
            guard let upper = index(startIndex, offsetBy: upTo.upperBound, limitedBy: endIndex) else {
                return
            }
            replaceSubrange(startIndex ..< upper, with: newValue)
        }
    }

    public subscript(nsrange: NSRange) -> String {
        get {
            return String(self[Range(nsrange, in: self) ?? startIndex ..< startIndex])
        }
        set {
            replaceSubrange(Range(nsrange, in: self) ?? startIndex ..< endIndex, with: newValue)
        }
    }
}

extension SqliteDatabase {

    @discardableResult public func perform<T, R>(_ statement: @autoclosure () throws -> Statement<T, R>) throws -> R {
        return try statement().run(self)
    }

    @discardableResult public func evaluate<T, R>(_ statement: @autoclosure () throws -> Statement<T, R>) -> R? {
        return try? statement().run(self)
    }
}

extension Collection where Element: SignedNumeric {

    public func diff() -> [Element] {
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
    public func lighter(by percentage: CGFloat = 30.0) -> UIColor {
        return self.adjustBrightness(by: abs(percentage))
    }

    /**
     Create a darker color
     */
    public func darker(by percentage: CGFloat = 30.0) -> UIColor {
        return self.adjustBrightness(by: -abs(percentage))
    }

    /**
     Try to increase brightness or decrease saturation
     */
    public func adjustBrightness(by percentage: CGFloat = 30.0) -> UIColor {
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
    public var components: DateComponents {
        if let comp = objc_getAssociatedObject(self, &Date.compKey) as? DateComponents {
            return comp
        } else {
            let comp = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond, .year, .month, .day], from: self)
            objc_setAssociatedObject(self, &Date.compKey, comp, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return comp
        }
    }
    public var midnightBefore: Date {
        var c = components
        c.hour = 0
        c.minute = 0
        c.second = 0
        return c.date
    }
    public var midnight: Date {
        return midnightBefore + 1.d
    }
    public var day: Int {
        return components.day ?? 0
    }
    public var month: Int {
        return components.month ?? 0
    }
    public var year: Int {
        return components.year ?? 0
    }
    public var hour: Int {
        return components.hour ?? 0
    }
    public var minute: Int {
        return components.minute ?? 0
    }
    public var second: Int {
        return components.second ?? 0
    }
}

extension DateComponents {
    public var date: Date {
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
    public var uint16: UInt16 {
        return UInt16(self[0]) << 8 + UInt16(self[1])
    }

    public func uint16(_ idx: Int) -> UInt16 {
        return UInt16(self[idx * 2]) << 8 + UInt16(self[idx * 2 + 1])
    }

    public var hexString: String {
        return reduce(into: "") {
            $0.append(hexDigits[Int($1 / 16)])
            $0.append(hexDigits[Int($1 % 16)])
        }
    }
}

extension Array where Element: Numeric, Element: Comparable {
    public func sum() -> Element {
        return reduce(0, +)
    }

    public func biggest() -> Element {
         return reduce(self[0]) { Swift.max($0, $1) }
    }

    public func smallest() -> Element {
        return reduce(self[0]) { Swift.min($0, $1) }
    }
}

extension Array where Element == Double {
    public func median() -> Double {
        return percentile(0.5)
    }

    public func percentile(_ p:Double) -> Double {
        guard count > 1 else {
            return self[0]
        }
        let idx0 = Int(floor(Double(count - 1) * p))
        let idx1 = Int(ceil(Double(count - 1) * p))
        if idx0 == idx1 {
            return self[idx1]
        } else {
            let f = 1 / Double(count - 1)
            return (p - Double(idx0) * f) / f * self[idx0] + (1 - (p - Double(idx0) * f) / f) * self[idx1]
        }
    }
}

extension Bundle {
    public static var documentsPath: String {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    }
}

extension Int {
    public var s: TimeInterval {
        return TimeInterval(self)
    }
    public var m: TimeInterval {
        return Double(self) * 60.0
    }
    public var h: TimeInterval {
        return self.m * 60
    }
    public var d: TimeInterval {
        return self.h * 24
    }
}

extension UIView {
    public var width: CGFloat {
        return frame.width
    }
    public var height: CGFloat {
        return frame.height
    }
    @objc var borderColor: UIColor? {
        get {
            if let c = layer.borderColor {
                return UIColor(cgColor: c)
            }
            return nil
        }
        set {
            layer.borderColor = newValue?.cgColor
        }
    }
}

public func - (lhs: Date, rhs: Date) -> TimeInterval {
    return lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970
}

public func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

extension CGPoint {

    public func distance(to: CGPoint) -> CGFloat {
        return ((x - to.x) ** 2 + (y - to.y) ** 2) ** 0.5
    }
}

precedencegroup PowerPrecedence {
    higherThan: MultiplicationPrecedence
}

infix operator **: PowerPrecedence

public func ** (lhs: CGFloat, rhs: CGFloat) -> CGFloat {
    return pow(lhs, rhs)
}

public func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

public func < (lhs: CGPoint, rhs: CGFloat) -> Bool {
    return abs(lhs.x) < rhs && abs(lhs.y) < rhs
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