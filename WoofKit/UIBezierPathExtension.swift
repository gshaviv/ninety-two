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
