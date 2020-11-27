//
//  WatchExtensions.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import CoreGraphics
import WatchKit

extension DateComponents {
    public var getDate: Date {
        return Calendar.current.date(from: self) ?? Date(timeIntervalSince1970: 0)
    }
}
private let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
private let months = ["Jan","Feb","Mar","Apr","May","June","July","Aug","Sep","Oct","Nov","Dec"]

extension Date {
    private static var compKey = false
    var components: DateComponents {
        if let comp = objc_getAssociatedObject(self, &Date.compKey) as? DateComponents {
            return comp
        } else {
            let comp = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond, .year, .month, .day, .weekday], from: self)
            objc_setAssociatedObject(self, &Date.compKey, comp, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return comp
        }
    }
    public var weekDay: Int {
        components.weekday ?? 0
    }
    public var weekDayName: String {
        days[weekDay - 1]
    }
    
    var day: Int {
        components.day ?? 0
    }
    var month: Int {
        components.month ?? 0
    }
    var monthName: String {
        months[month - 1]
    }
    var year: Int {
        components.year ?? 0
    }
    var hour: Int {
        components.hour ?? 0
    }
    var minute: Int {
        components.minute ?? 0
    }
    var second: Int {
         components.second ?? 0
    }
    public func isOnSameDay(as date: Date) -> Bool {
        day == date.day && month == date.month && year == date.year
    }
}

extension CGRect {
    public init(center: CGPoint, size: CGSize) {
        self.init(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

public extension Collection {
    func countMatches(where test: (Element) throws -> Bool) rethrows -> Int {
        return try self.filter(test).count
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

extension Double {
    public func decimal(digits n:Int) -> Decimal {
        var rounded = Decimal()
        var initial = Decimal(self)
        NSDecimalRound(&rounded, &initial, n, .plain)
        return rounded
    }
    
    public func maxDigits(_ n: Int) -> String {
        let str = String(format:"%.\(n)lf",self)
        guard str.contains(".") else {
            return str
        }
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

func - (lhs: Date, rhs: Date) -> TimeInterval {
    return lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970
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

func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

extension UIImage {
//    func tint(color: UIColor) -> UIImage {
//        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
//        color.setFill()
//        
//        let context = UIGraphicsGetCurrentContext()
//        context?.translateBy(x: 0, y: self.size.height)
//        context?.scaleBy(x: 1.0, y: -1.0)
//        context?.setBlendMode(CGBlendMode.normal)
//        
//        let rect = CGRect(origin: .zero, size: CGSize(width: self.size.width, height: self.size.height))
//        context?.clip(to: rect, mask: self.cgImage!)
//        context?.fill(rect)
//        
//        let newImage = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        
//        return newImage!
//    }
    
    func tint(with color: UIColor) -> UIImage {
        let image = withRenderingMode(.alwaysTemplate)
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        color.set()
        image.draw(in: CGRect(origin: .zero, size: size))
        
        guard let imageColored = UIGraphicsGetImageFromCurrentImageContext() else {
            return UIImage()
        }
        
        UIGraphicsEndImageContext()
        return imageColored
    }

}
