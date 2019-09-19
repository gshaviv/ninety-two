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
