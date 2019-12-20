//
//  UIBezierPathExtension.swift
//  SmoothScribble
//
//  Created by Simon Gladman on 04/11/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//

import UIKit

extension UIBezierPath {
    public func interpolate(points interpolationPoints: ArraySlice<CGPoint>, step: CGFloat = 1) {
        interpolate(points: Array(interpolationPoints), step: step)
    }

    public func interpolate(points inputPoints: [CGPoint], step: CGFloat = 1) {
        guard inputPoints.count > 1 else {
            return
        }
        let signedStep: CGFloat = inputPoints.last!.x > inputPoints.first!.x ? 1 : -1
        var points = [inputPoints.first!]
        for point in inputPoints[1...] {
            if signedStep > 0 {
                if points.last!.x < point.x {
                    points.append(point)
                }
            } else {
                if points.first!.x > point.x {
                    points.insert(point, at: 0)
                }
            }
        }
        let akima = AkimaInterpolator(points: points)
        var isFirst = true
        for x in stride(from: inputPoints.first!.x, to: inputPoints.last!.x, by: abs(step) * signedStep) {
            let point = CGPoint(x: x, y: akima.interpolateValue(at: x))
            if isFirst {
                isFirst = false
                move(to: point)
            } else {
                addLine(to: point)
            }
        }
    }
}

public class Plot {
    let akima: AkimaInterpolator

    public init(points inputPoints: [CGPoint]) {
        let points: [CGPoint] = inputPoints.last!.x > inputPoints.first!.x ? inputPoints : inputPoints.reversed()
//        let signedStep: CGFloat = inputPoints.last!.x > inputPoints.first!.x ? 1 : -1
//        var points = [inputPoints.first!]
//        for point in inputPoints[1...] {
//            if signedStep > 0 {
//                if points.last!.x < point.x {
//                    points.append(point)
//                }
//            } else {
//                if points.first!.x > point.x {
//                    points.insert(point, at: 0)
//                }
//            }
//        }
        akima = AkimaInterpolator(points: points)
    }

    public func line(from x0: CGFloat, to x1: CGFloat, moveToFirst: Bool = true) -> UIBezierPath {
        let path = UIBezierPath()
        line(in: path, from: x0, to: x1, moveToFirst: moveToFirst)
        return path
    }

    public func line(in path: UIBezierPath, from x0: CGFloat, to x1: CGFloat, moveToFirst: Bool = true) {
        var isFirst = moveToFirst
        for x in stride(from: x0, to: x1, by: x1 > x0 ? 1 : -1) {
            let point = CGPoint(x: x, y: akima.interpolateValue(at: x))
            if isFirst {
                isFirst = false
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
    }
    
    public func coloredLines(from x0: CGFloat, to x1: CGFloat) -> [(UIColor, UIBezierPath)] {
        var out = [(UIColor, UIBezierPath)]()
        var curve: UIBezierPath?
        var currentColor = UIColor.blue
        for x in stride(from: x0, to: x1, by: x1 > x0 ? 1 : -1) {
            let point = CGPoint(x: x, y: akima.interpolateValue(at: x))
            let pointColor = colorForValue(point.y)
            if pointColor != currentColor {
                if let curve = curve {
                    curve.addLine(to: point)
                    out.append((currentColor, curve))
                }
                curve = UIBezierPath()
                curve?.move(to: point)
            } else {
                curve?.addLine(to: point)
            }
            currentColor = pointColor
        }
        if let curve = curve {
            out.append((currentColor, curve))
        }
        return out
    }

    public func value(at x: CGFloat) -> CGFloat {
        if x > akima.maxX {
            return akima.interpolateValue(at: akima.maxX)
        } else {
            return akima.interpolateValue(at: x)
        }
    }

    public func intersects(_ rect: CGRect) -> Bool {
        var isAbove: Bool? = nil
        var values = [CGFloat]()
        var x = rect.minX
        if akima.maxX < x {
            return false
        }
        while x < rect.maxX {
            values.append(x)
            x += max(rect.width / 10, 2)
        }
        if x < rect.maxX {
            values.append(rect.maxX)
        }
        for x in values {
            if akima.maxX < x {
                continue
            }
            let y = value(at: x)
            if let isAbove = isAbove {
                if isAbove {
                    if y > rect.maxY {
                        continue
                    }
                } else {
                    if y < rect.minY {
                        continue
                    }
                }
                return true
            } else {
                if y < rect.minY {
                    isAbove = false
                } else if y > rect.maxY {
                    isAbove = true
                } else {
                    return true
                }
            }
        }
        return false
    }

    private var colors: [Range<CGFloat> : UIColor]!
    
    public func set(colors c: [(CGFloat,UIColor)]) {
        colors = [:]
        var lower:CGFloat = -CGFloat.greatestFiniteMagnitude
        for (upper,color) in c.reversed() {
            colors![lower ..< upper] = color
            lower = upper
        }
    }
    
    public  func colorForValue(_ v: CGFloat) -> UIColor {
        for (range,color) in colors {
            if range.contains(v) {
                return color
            }
        }
        return UIColor.black
    }
}
