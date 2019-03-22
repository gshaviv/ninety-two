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

extension CGRect {
    public init(center: CGPoint, size: CGSize) {
        self.init(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

extension CGGradient {
    public static func with(colors:[UIColor], locations:[CGFloat]) -> CGGradient {
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map{$0.cgColor} as CFArray, locations: locations)!
    }
}

extension Array where Element: Sqlable {
    public func insert(into: SqliteDatabase) throws {
        try into.transaction { db in
            forEach {
                db.evaluate($0.insert())
            }
        }
    }
}

extension Array where Element: Hashable {
    public func unique() -> [Element] {
        return Array(reduce(into: Set<Element>()) { $0.insert($1) })
    }
}


extension SqliteDatabase {
    static private let dbQueue = DispatchQueue(label: "db")

    @discardableResult public func perform<T, R>(_ statement: @autoclosure () throws -> Statement<T, R>) throws -> R {
        return try SqliteDatabase.dbQueue.sync {
            try statement().run(self)
        }
    }

    @discardableResult public func evaluate<T, R>(_ statement: @autoclosure () throws -> Statement<T, R>) -> R? {
        var result: R?
        SqliteDatabase.dbQueue.sync {
            result = try? statement().run(self)
        }
        return result
    }

//    @discardableResult public func execute(_ sqlString: String, values: [SqlType]) -> [Any] {
//        guard let sql = sqlString.cString(using: String.Encoding.utf8) else {
//            fatalError("Invalid SQL")
//        }
//        var handlePointer : OpaquePointer? = nil
//        if sqlite3_prepare_v2(db, sql, -1, &handlePointer, nil) != SQLITE_OK {
//            try throwLastError(db)
//        }
//        guard let handle = handlePointer else {
//            fatalError("No SQL handle received")
//        }
//        try bindValues(db, handle: handle, values: statement.values, from: 1)
//
//        var returnValue = [Any]()
//        loop: while true {
//            switch sqlite3_step(handle) {
//            case SQLITE_ROW:
//                returnValue.append(try T(row: ReadRow(handle: handle, tablename: T.tableName), db: self))
//                continue
//            case SQLITE_DONE: break loop
//            }
//        }
//    }
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

extension Double {
    public func significantDigits(_ n: Int) -> String {
        let str = formatted(with: "%.\(n)lf")
        var idx = str.endIndex
        while idx != str.startIndex  {
            idx = str.index(before: idx)
            if str[idx] == "0" {
                continue
            }
            break
        }
        if str[idx] == "." {
            if idx == str.startIndex {
                return "0"
            }
            idx = str.index(before: idx)
        }
        let trimmed = str[...idx]
        return trimmed.isEmpty ? "0" : String(trimmed)
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
            let comp = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond, .year, .month, .day, .weekday], from: self)
            objc_setAssociatedObject(self, &Date.compKey, comp, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return comp
        }
    }
    public var startOfDay: Date {
        var c = components
        c.hour = 0
        c.minute = 0
        c.second = 0
        return c.toDate()
    }
    public var endOfDay: Date {
        return startOfDay + 1.d
    }
    public var day: Int {
        return components.day ?? 0
    }
    public var weekDay: Int {
        return components.weekday ?? 0
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

extension UIImage {
    public class func imageWithColor(_ color: UIColor) -> UIImage {
        return UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: 0, width: 1, height: 1)).image(actions: { (ctx) in
            color.set()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        })
    }
}

extension DateComponents {
    public func toDate() -> Date {
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

extension UIView {
    public var controller: UIViewController? {
        var responder = self.next
        repeat {
            if let vc = responder as? UIViewController {
                return vc
            }
            responder = responder?.next
        } while responder != nil
        return nil
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
    public var mo: TimeInterval {
        return self.d * 30
    }
    public var y: TimeInterval {
        return self.d * 365
    }
}

precedencegroup TimeConcat {
    higherThan: MultiplicationPrecedence
}

infix operator ⁚: TimeConcat

public func ⁚ (lhs: TimeInterval, rhs: TimeInterval) -> TimeInterval {
    return lhs + rhs
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

public func ** (lhs: Double, rhs: Double) -> Double {
    return pow(lhs, rhs)
}

public func ** (lhs: Double, rhs: Int) -> Double {
    return pow(lhs, Double(rhs))
}

public func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

public func < (lhs: CGPoint, rhs: CGFloat) -> Bool {
    return abs(lhs.x) < rhs && abs(lhs.y) < rhs
}

extension Date {
    public var rounded: Date {
        var comp = components
        if comp.minute ?? 0 > 59 {
            comp.hour = (comp.hour ?? 0) + 1
        }
        comp.minute = Int(round(Double(comp.minute ?? 0)))
        return comp.toDate()
    }
}

public extension DispatchQueue {
    public func after(withDelay delay: Double, closure: @escaping (() -> Void)) {
        let dispatchTime: DispatchTime = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        asyncAfter(deadline: dispatchTime, execute: closure)
    }
}

public class FilePointer: NSObject, NSFilePresenter {
    public var presentedItemURL: URL?

    public var presentedItemOperationQueue: OperationQueue

    public init(url: URL, queue: OperationQueue? = nil) {
        presentedItemURL = url
        presentedItemOperationQueue = queue ?? OperationQueue.main
    }
}

extension UIColor {
    public convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        let divisor = CGFloat(255)
        let red = CGFloat((rgb & 0xFF0000) >> 16) / divisor
        let green = CGFloat((rgb & 0x00FF00) >> 8) / divisor
        let blue = CGFloat(rgb & 0x0000FF) / divisor
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    public var rgbValue: UInt32 {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        
        return UInt32(r * 255) << 16 + UInt32(g * 255) << 8 + UInt32(b * 255)
    }
}
