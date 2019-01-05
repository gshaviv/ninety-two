//
//  GlucoseGraph.swift
//
//
//  Created by Guy on 27/12/2018.
//

import UIKit
import CoreGraphics

@IBDesignable
class GlucoseGraph: UIView {
    var points: [GlucoseReading]! {
        didSet {
            guard !points.isEmpty else {
                return
            }
            let (gmin, gmax) = points.reduce((999.0, 0.0)) { (min($0.0, $1.value), max($0.1, $1.value)) }
            holes = []
            for (idx, gp) in points[1...].enumerated() {
                if gp.isCalibration {
                    holes.append(idx + 1)
                } else if gp.date - points[idx].date > 30.m {
                    holes.append(idx + 1)
                }
            }
            yRange.min = max(CGFloat(floor(gmin / 5) * 5), 10)
            yRange.max = CGFloat(ceil(gmax / 5) * 5)
            contentWidthConstraint?.isActive = false
            contentWidthConstraint = (contentView[.width] == self[.width] * CGFloat((xRange.max - xRange.min) / xTimeSpan))
            setNeedsLayout()
            DispatchQueue.main.async {
                self.contentHolder.contentOffset = CGPoint(x: self.contentHolder.contentSize.width - self.contentHolder.width, y: 0)
            }
        }
    }
    private var holes: [Int] = []
    var yRange = (min: CGFloat(70), max: CGFloat(180))
    var xRange = (min: Date() - 1.d, max: Date())
    var lineWidth: CGFloat = 1.5
    var dotRadius: CGFloat = 3
    var xTimeSpan = 6.h {
        didSet {
            contentWidthConstraint?.isActive = false
            contentWidthConstraint = (contentView[.width] == self[.width] * CGFloat((xRange.max - xRange.min) / xTimeSpan))
            setNeedsLayout()
        }
    }

    var contentHolder: UIScrollView!
    var contentView: DrawingView!
    var xAxisHolder: UIScrollView!
    var xAxis: DrawingView!
    var xAxisHeight: CGFloat = 30
    var yAxis: DrawingView!

    let colors = [0 ... 55: UIColor.red,
                   55 ... 70: UIColor.red.lighter(),
                   70 ... 110: UIColor.green,
                   110 ... 140: UIColor.green.lighter(by: 40),
                   140 ... 180: UIColor.green.lighter(by: 70),
                   180 ... 999: UIColor.yellow]
    var contentWidthConstraint: NSLayoutConstraint?

    var yReference = [35, 40, 50, 60, 70, 90, 110, 125, 140, 160, 180, 200, 250, 300, 350, 400, 500]

    private func drawContent(_ rect: CGRect) {
        guard let points = self.points else {
            return
        }
        let ctx = UIGraphicsGetCurrentContext()
        let size = self.contentView.bounds.size
        let yScale = size.height / (self.yRange.max - self.yRange.min)
        let yCoor = { (self.yRange.max - $0) * yScale }
        let xScale = rect.size.width / CGFloat(self.xRange.max - self.xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - self.xRange.min) * xScale }
        for (range, color) in self.colors {
            color.set()
            ctx?.fill(CGRect(x: 0.0, y: yCoor(CGFloat(range.upperBound)), width: size.width, height: CGFloat(range.upperBound - range.lowerBound) * yScale))
        }
        UIColor(white: 0.5, alpha: 0.5).set()
        ctx?.beginPath()
        for y in self.yReference {
            let yc = yCoor(CGFloat(y))
            ctx?.move(to: CGPoint(x: 0, y: yc))
            ctx?.addLine(to: CGPoint(x: rect.width, y: yc))
        }
        ctx?.strokePath()
        let p = points.map { CGPoint(x: xCoor($0.date), y: yCoor(CGFloat($0.value))) }
        if p.isEmpty {
            return
        }
        let curve = UIBezierPath()
        if self.holes.isEmpty {
            curve.move(to: p[0])
            curve.addCurveThrough(points: p[1...], contractionFactor: 0.65)
        } else {
            var idx = 0
            for hole in self.holes {
                curve.move(to: p[idx])
                curve.addCurveThrough(points: p[idx ..< hole], contractionFactor: 0.65)
                idx = hole
            }
            if idx < p.count - 1 {
                curve.move(to: p[idx])
                curve.addCurveThrough(points: p[idx ..< p.count], contractionFactor: 0.65)
            }
        }
        UIColor.darkGray.set()
        curve.lineWidth = self.lineWidth
        curve.stroke()

        UIColor.black.set()
        let fill = UIBezierPath()
        let dotSize = CGSize(width: 2 * self.dotRadius, height: 2 * self.dotRadius)
        for point in p {
            fill.append(UIBezierPath(ovalIn: CGRect(origin: point - CGPoint(x: self.dotRadius, y: self.dotRadius), size: dotSize)))
        }
        fill.lineWidth = 0
        fill.fill()

        if let touchPoint = self.touchPoint {
            let coor = CGPoint(x: xCoor(touchPoint.date), y: yCoor(CGFloat(touchPoint.value)))
            UIColor.darkGray.set()
            ctx?.beginPath()
            ctx?.move(to: CGPoint(x: coor.x, y: rect.height))
            ctx?.addLine(to: coor)
            ctx?.addLine(to: CGPoint(x: rect.width, y: coor.y))
            ctx?.strokePath()
        }
    }

    private func drawXAxis(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()
        backgroundColor?.set()
        ctx?.fill(rect)
        UIColor.black.set()
        ctx?.setLineWidth(1)
        ctx?.beginPath()
        ctx?.move(to: CGPoint(x: 0, y: 0))
        ctx?.addLine(to: CGPoint(x: rect.width, y: 0))
        let xScale = rect.size.width / CGFloat(self.xRange.max - self.xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - self.xRange.min) * xScale }
        ctx?.strokePath()

        var touchLabelFrame: CGRect?
        if let touchPoint = self.touchPoint {
            let c = self.colors.filter({ $0.key.contains(Int(touchPoint.value)) }).last?.value ?? UIColor.blue.darker(by: 70)
            let str = String(format: "%02ld:%02ld", touchPoint.date.hour, touchPoint.date.minute).styled.systemFont(.bold, size: 14).color(c.darker(by: 50))
            let size = str.size()
            let p = CGPoint(x: xCoor(touchPoint.date) - size.width / 2, y: 3)
            touchLabelFrame = CGRect(origin: p, size: size)
            if touchLabelFrame!.maxY > rect.maxY {
                touchLabelFrame = CGRect(origin: CGPoint(x: rect.width - size.width, y: 3), size: size)
            }
            str.draw(in: touchLabelFrame!)
        }

        var components = self.xRange.min.components
        components.second = 0
        components.minute = 0
        var xDate = components.date
        let step: TimeInterval
        if self.xTimeSpan < 3.h {
            step = 30.m
        } else if self.xTimeSpan < 7.h {
            step = 1.h
        } else if self.xTimeSpan < 13.h {
            step = 2.h
        } else {
            step = 3.h
        }
        repeat {
            UIColor.black.set()
            ctx?.beginPath()
            ctx?.move(to: CGPoint(x: xCoor(xDate), y: 0))
            ctx?.addLine(to: CGPoint(x: xCoor(xDate), y: 5))
            let tick = xCoor(xDate + step / 2)
            ctx?.move(to: CGPoint(x: tick, y: 0))
            ctx?.addLine(to: CGPoint(x: tick, y: 3))
            ctx?.strokePath()
            let str = String(format: "%02ld:%02ld", xDate.hour, xDate.minute).styled.systemFont(size: 14)
            let size = str.size()
            let p = CGPoint(x: xCoor(xDate) - size.width / 2, y: 6)
            let stringRect = CGRect(origin: p, size: size)
            if rect.contains(stringRect) && (touchLabelFrame == nil || !touchLabelFrame!.intersects(stringRect)) {
                str.draw(in: stringRect)
            }
            xDate += step
        } while xDate < self.xRange.max
    }

    private func drawYAxis(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()
        UIColor.white.setFill()
        ctx?.fill(rect)
        let size = self.contentView.bounds.size
        let yScale = size.height / (self.yRange.max - self.yRange.min)
        let yCoor = { (y: Int) in (self.yRange.max - CGFloat(y)) * yScale }

        backgroundColor?.set()
        ctx?.fill(rect)

        UIColor.black.set()
        ctx?.beginPath()
        ctx?.move(to: CGPoint(x: 0, y: 0))
        ctx?.addLine(to: CGPoint(x: 0, y: size.height))
        ctx?.strokePath()

        let touchLabelFrame: CGRect?
        if let touchPoint = self.touchPoint {
            let v = Int(round(touchPoint.value))
            let c = self.colors.filter({ $0.key.contains(Int(touchPoint.value)) }).last?.value ?? UIColor.blue.darker(by: 70)
            let str = "\(v)".styled.systemFont(.bold, size: 14).color(c.darker(by: 50))
            let size = str.size()
            touchLabelFrame = CGRect(origin: CGPoint(x: 3, y: yCoor(v) - size.height / 2), size: size)
            str.draw(in: touchLabelFrame!)
        } else {
            touchLabelFrame = nil
        }

        for y in self.yReference {
            if CGFloat(y) < self.yRange.min || CGFloat(y) > self.yRange.max {
                continue
            }
            ctx?.beginPath()
            ctx?.move(to: CGPoint(x: 0, y: yCoor(y)))
            ctx?.addLine(to: CGPoint(x: 5, y: yCoor(y)))
            ctx?.strokePath()
            let label = "\(y)".styled.systemFont(size: 14)
            let size = label.size()
            let labelFrame = CGRect(origin: CGPoint(x: 6, y: yCoor(y) - size.height / 2), size: size)
            if rect.contains(labelFrame) && (touchLabelFrame == nil || !touchLabelFrame!.intersects(labelFrame)) {
                label.draw(in: labelFrame)
            }
        }
    }

    private func commonInit() {
        contentHolder = UIScrollView(frame: .zero)
        contentHolder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentHolder)
        contentHolder.delegate = self

        contentView = DrawingView { [weak self] (rect) in
            self?.drawContent(rect)
        }
        contentHolder.addSubview(contentView)

        makeConstraints {
            contentHolder[.top] == self[.top]
            contentHolder[.left] == self[.left]
            self[.bottom] == contentHolder[.bottom] + xAxisHeight
            contentHolder[.right] == self[.right] - 40 ~ 900

            contentView[.top] == contentHolder[.top]
            contentView[.bottom] == contentHolder[.bottom]
            contentView[.left] == contentHolder[.left]
            contentView[.right] == contentHolder[.right]
            contentView[.height] == self[.height] - xAxisHeight ~ 900
        }

        xAxisHolder = UIScrollView(frame: .zero)
        xAxisHolder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(xAxisHolder)
        xAxisHolder.isScrollEnabled = false
        makeConstraints {
            xAxisHolder[.left] == self[.left]
            self[.right] == xAxisHolder[.right] + 40
            xAxisHolder[.bottom] == self[.bottom]
            xAxisHolder[.height] == xAxisHeight
        }

        xAxis = DrawingView { [weak self] (rect) in
            self?.drawXAxis(rect)
        }
        xAxisHolder.addSubview(xAxis)
        makeConstraints {
            xAxis[.top] == xAxisHolder[.top]
            xAxis[.bottom] == xAxisHolder[.bottom]
            xAxis[.left] == xAxisHolder[.left]
            xAxis[.right] == xAxisHolder[.right]
            xAxis[.height] == xAxisHeight
            xAxis[.width] == contentView[.width]
        }

        yAxis = DrawingView { [weak self] (rect) in
            self?.drawYAxis(rect)
        }
        addSubview(yAxis)
        makeConstraints {
            yAxis[.top] == self.contentHolder[.top]
            yAxis[.left] == self.contentHolder[.right]
            yAxis[.bottom] == self[.bottom]
            yAxis[.right] == self[.right]
        }

        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.setNeedsDisplay()
        xAxis.setNeedsDisplay()
        yAxis.setNeedsDisplay()
    }

    var touchPoint: GlucoseReading? {
        didSet {
            contentView.setNeedsDisplay()
            xAxis.setNeedsDisplay()
            yAxis.setNeedsDisplay()
        }
    }

    @objc private func handleTap(_ sender: UIGestureRecognizer) {
        let touchPoint = sender.location(in: contentView)
        let size = self.contentView.bounds.size
        let yScale = size.height / (self.yRange.max - self.yRange.min)
        let yCoor = { (self.yRange.max - $0) * yScale }
        let xScale = size.width / CGFloat(self.xRange.max - self.xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - self.xRange.min) * xScale }
        let pts = self.points!.map { (CGPoint(x: xCoor($0.date), y: yCoor(CGFloat($0.value))), $0) }
        let inside = pts.filter { $0.0 - touchPoint < 50 }
        if inside.isEmpty {
            self.touchPoint = nil
            return
        }
        var best = inside[0].1
        var dist: CGFloat = touchPoint.distance(to: inside[0].0)
        for point in inside[1...] {
            let h = touchPoint.distance(to: point.0)
            if h < dist {
                dist = h
                best = point.1
            }
        }
        self.touchPoint = best
    }
}

extension GlucoseGraph: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        xAxisHolder.contentOffset = scrollView.contentOffset
        if touchPoint != nil {
            touchPoint = nil
        }
    }
}

extension GlucoseGraph {

    override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        points = [
            GlucosePoint(date: Date() - 1.d, value: 70),
            GlucosePoint(date: Date() - 23.h, value: 80),
            GlucosePoint(date: Date() - 22.h, value: 100),
            GlucosePoint(date: Date() - 21.h, value: 119),
            GlucosePoint(date: Date() - 20.h, value: 126),
            GlucosePoint(date: Date() - 19.h, value: 140),
            GlucosePoint(date: Date() - 18.h, value: 150),
            GlucosePoint(date: Date() - 17.h, value: 145),
            GlucosePoint(date: Date() - 16.h, value: 153),
            GlucosePoint(date: Date() - 15.h, value: 134),
            GlucosePoint(date: Date() - 14.h, value: 120),
            GlucosePoint(date: Date() - 10.h, value: 100),
            GlucosePoint(date: Date() - 8.h, value: 75),
            GlucosePoint(date: Date() - 6.h, value: 65),
            GlucosePoint(date: Date() - 4.h, value: 64),
            GlucosePoint(date: Date() - 2.h, value: 70),
            GlucosePoint(date: Date() - 1.h, value: 75),
            GlucosePoint(date: Date() - 55.m, value: 80),
            GlucosePoint(date: Date(), value: 90)
        ]
    }
}
