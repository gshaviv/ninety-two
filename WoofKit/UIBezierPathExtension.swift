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
            let point = CGPoint(x: x, y: akima.interpolate(value: x))
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
        akima = AkimaInterpolator(points: points)
    }

    public func line(from x0: CGFloat, to x1: CGFloat, moveToFirst: Bool = true) -> UIBezierPath {
        let path = UIBezierPath()
        var isFirst = moveToFirst
        for x in stride(from: x0, to: x1, by: 1) {
            let point = CGPoint(x: x, y: akima.interpolate(value: x))
            if isFirst {
                isFirst = false
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    public func value(at x: CGFloat) -> CGFloat {
        return akima.interpolate(value: x)
    }

    public func intersects(_ rect: CGRect) -> Bool {
        var isAbove: Bool? = nil
        var values = [CGFloat]()
        var x = rect.minX
        while x < rect.maxX {
            values.append(x)
            x += max(rect.width / 10, 2)
        }
        if x < rect.maxX {
            values.append(rect.maxX)
        }
        for x in values {
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

}
