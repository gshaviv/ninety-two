//
//  PieChart.swift
//  WoofWoof
//
//  Created by Guy on 30/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import UIKit

@IBDesignable
class PieChart: UIView {
    struct Slice {
        let value: CGFloat
        let color: UIColor
    }
    var slices: [Slice] = [] {
        didSet {
            sum = slices.reduce(0) { $0 + $1.value }
            setNeedsDisplay()
        }
    }
    var sum: CGFloat = 0

    override func setNeedsLayout() {
        super.setNeedsLayout()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()
        UIColor.white.set()
        ctx?.fill(rect)
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var angle: CGFloat = 0
        for (idx, slice) in slices.enumerated() {
            let endAngle = (idx == slices.count - 1 ? 2 * .pi : (slice.value / sum) * 2 * .pi + angle)
            slice.color.setFill()
            ctx?.beginPath()
            ctx?.move(to: center)
            ctx?.addArc(center: center, radius: radius, startAngle: angle, endAngle: endAngle, clockwise: false)
            ctx?.fillPath()
            angle = endAngle
        }
        UIColor.lightGray.set()
        UIBezierPath(ovalIn: CGRect(origin: center - CGPoint(x: radius, y: radius), size: CGSize(width: 2*radius, height: 2*radius))).stroke()
    }
}

extension PieChart {
    override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        slices = [Slice(value: 1, color: .red),
                  Slice(value: 1, color: .yellow),
                  Slice(value: 3, color: .green)]
    }
}
