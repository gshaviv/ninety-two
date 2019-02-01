//
//  GlucoseGraph.swift
//
//
//  Created by Guy on 27/12/2018.
//

import UIKit
import CoreGraphics

public protocol GlucoseGraphDelegate: class {
    func didTouch(record: Record)
    func didDoubleTap(record: Record)
}

extension GlucoseGraphDelegate {
    public func didDoubleTap(record: Record) { }
}

public struct Prediction {
    public let highDate: Date
    public let h25: CGFloat
    public let h50: CGFloat
    public let h75: CGFloat
    public let mealTime: Date
    public let low: CGFloat

    public init(mealTime: Date, highDate: Date, h25: CGFloat, h50: CGFloat, h75: CGFloat,  low: CGFloat) {
        self.highDate = highDate
        self.h25 = h25
        self.h50 = h50
        self.h75 = h75
        self.mealTime = mealTime
        self.low = low
    }
}

public struct Pattern {
    public let p10: [Double]
    public let p25: [Double]
    public let p50: [Double]
    public let p75: [Double]
    public let p90: [Double]

    public init(p10: [Double], p25: [Double], p50: [Double], p75: [Double], p90: [Double]) {
        self.p10 = p10
        self.p25 = p25
        self.p50 = p50
        self.p75 = p75
        self.p90 = p90
    }
}


@IBDesignable
public class GlucoseGraph: UIView {
    private var touchables:[(CGRect, Record)] = []
    public weak var delegate: GlucoseGraphDelegate?
    @IBInspectable var isScrollEnabled:Bool = true
    public var points: [GlucoseReading]! {
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
    public var yRange = (min: CGFloat(70), max: CGFloat(180))
    public var xRange = (min: Date() - 1.d, max: Date())
    public var lineWidth: CGFloat = 1.5
    public var dotRadius: CGFloat = 3
    public var xTimeSpan = 6.h {
        didSet {
            contentWidthConstraint?.isActive = false
            contentWidthConstraint = (contentView[.width] == self[.width] * CGFloat((xRange.max - xRange.min) / xTimeSpan))
            setNeedsLayout()
        }
    }
    public var records: [Record] = [] {
        didSet {
            contentView.setNeedsDisplay()
        }
    }
    public var prediction: Prediction? {
        didSet {
            contentView.setNeedsDisplay()
        }
    }
    public var pattern: Pattern? {
        didSet {
            contentView.setNeedsDisplay()
        }
    }
    private var contentHolder: UIScrollView!
    private var contentView: DrawingView!
    private var xAxisHolder: UIScrollView!
    private var xAxis: DrawingView!
    private var xAxisHeight: CGFloat = 30
    private var yAxis: DrawingView!


    private var contentWidthConstraint: NSLayoutConstraint?

    public var yReference = [35, 40, 50, 60, 70, 80, 90, 100, 120, 140, 160, 180, 200, 225, 250, 275, 300, 350, 400, 500]

    private func drawContent(_ rect: CGRect) {
        let colors = [(defaults[.level0], defaults[.color0]),
                      (defaults[.level1], defaults[.color1]),
                      (defaults[.level2], defaults[.color2]),
                      (defaults[.level3], defaults[.color3]),
                      (defaults[.level4], defaults[.color4]),
                      (999.0, defaults[.color5])]
        guard let points = points else {
            return
        }
        let ctx = UIGraphicsGetCurrentContext()
        let size = contentView.bounds.size
        let yScale = size.height / (yRange.max - yRange.min)
        let yCoor = { (self.yRange.max - $0) * yScale }
        let xScale = rect.size.width / CGFloat(xRange.max - xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - self.xRange.min) * xScale }
        var lower:Double = 0
        for (upper, color) in colors {
            color.set()
            let r = CGRect(x: 0.0, y: yCoor(CGFloat(upper)), width: size.width, height: CGFloat(upper - lower) * yScale)
            ctx?.fill(r)
            lower = upper
        }
        UIColor(white: 0.5, alpha: 0.5).set()
        ctx?.beginPath()
        for y in yReference {
            let yc = yCoor(CGFloat(y))
            ctx?.move(to: CGPoint(x: 0, y: yc))
            ctx?.addLine(to: CGPoint(x: rect.width, y: yc))
        }
        var components = xRange.min.components
        components.second = 0
        components.minute = 0
        var xDate = components.toDate()
        let step: TimeInterval
        if xTimeSpan < 3.h {
            step = 30.m
        } else if xTimeSpan < 7.h {
            step = 1.h
        } else if xTimeSpan < 13.h {
            step = 2.h
        } else {
            step = 3.h
        }
        repeat {
            ctx?.move(to: CGPoint(x: xCoor(xDate), y: 0))
            ctx?.addLine(to: CGPoint(x: xCoor(xDate), y: size.height))
            xDate += step
        } while xDate < xRange.max
        ctx?.strokePath()
        let p = points.map { CGPoint(x: xCoor($0.date), y: yCoor(CGFloat($0.value))) }
        if p.isEmpty {
            return
        }
        if let prediction = prediction {
            ctx?.saveGState()
            ctx?.setLineWidth(3)
            UIColor.blue.withAlphaComponent(0.5).set()
            ctx?.saveGState()
            ctx?.setLineDash(phase: 0, lengths: [8,6])
            ctx?.beginPath()
            ctx?.move(to: CGPoint(x: xCoor(prediction.highDate), y: yCoor(prediction.low)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate + 5.h), y: yCoor(prediction.low)))
            ctx?.move(to: CGPoint(x: xCoor(prediction.mealTime), y: yCoor(prediction.h75)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate - 30.m), y: yCoor(prediction.h75)))
            ctx?.move(to: CGPoint(x: xCoor(prediction.mealTime), y: yCoor(prediction.h50)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate - 30.m), y: yCoor(prediction.h50)))
            ctx?.strokePath()
            ctx?.restoreGState()
            ctx?.beginPath()
            ctx?.move(to: CGPoint(x: xCoor(prediction.highDate - 30.m), y: yCoor(prediction.h50)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate + 30.m), y: yCoor(prediction.h50)))
            ctx?.move(to: CGPoint(x: xCoor(prediction.highDate - 30.m), y: yCoor(prediction.h75)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate + 30.m), y: yCoor(prediction.h75)))
            ctx?.strokePath()
            ctx?.restoreGState()
        }
        if let pattern = pattern {
            let xPos = { (i: Int) in (CGFloat(i) - 0.5) / 24 * self.contentView.bounds.width }

            ctx?.saveGState()
            let a10 = UIBezierPath()
            let coor10 = pattern.p10.enumerated().map { CGPoint(x: xPos($0.0), y: yCoor(CGFloat($0.1))) }
            let coor90 = Array(pattern.p90.enumerated().map { CGPoint(x: xPos($0.0), y: yCoor(CGFloat($0.1))) }.reversed())
            a10.move(to: coor10[0])
            a10.addCurveThrough(points: coor10[1...])
            a10.addLine(to: coor90[0])
            a10.addCurveThrough(points: coor90[1...])
            a10.addLine(to: coor10[0])

            let coor25 = pattern.p25.enumerated().map { CGPoint(x: xPos($0.0), y: yCoor(CGFloat($0.1))) }
            let coor75 = Array(pattern.p75.enumerated().map { CGPoint(x: xPos($0.0), y: yCoor(CGFloat($0.1))) }.reversed())
            let a25 = UIBezierPath()
            a25.move(to: coor25[0])
            a25.addCurveThrough(points: coor25[1...])
            a25.addLine(to: coor75[0])
            a25.addCurveThrough(points: coor75[1...])
            a25.addLine(to: coor25[0])

            let coor50 = pattern.p50.enumerated().map { CGPoint(x: xPos($0.0), y: yCoor(CGFloat($0.1))) }
            let median = UIBezierPath()
            median.move(to: coor50[0])
            median.addCurveThrough(points: coor50[1...])

            UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.1).setFill()
            a10.fill()
            UIColor(red: 0.2, green: 0.2, blue: 0.4, alpha: 0.1).set()
            a25.fill()
            UIColor.black.withAlphaComponent(0.1).set()
            median.lineWidth = 3
            median.stroke()
            ctx?.restoreGState()
        }
        let curve = UIBezierPath()
        if holes.isEmpty {
            curve.move(to: p[0])
            curve.addCurveThrough(points: p[1...], contractionFactor: 0.65)
        } else {
            var idx = 0
            for hole in holes {
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
        curve.lineWidth = lineWidth
        curve.stroke()

        let fill = UIBezierPath()
        let trend = UIBezierPath()
        let dotSize = CGSize(width: 2 * dotRadius, height: 2 * dotRadius)
        for (idx,point) in p.enumerated() {
            let path: UIBezierPath
            if let gp = points[idx] as? GlucosePoint {
                path = gp.isTrend ? trend : fill
            } else {
                path = fill
            }
            path.append(UIBezierPath(ovalIn: CGRect(origin: point - CGPoint(x: dotRadius, y: dotRadius), size: dotSize)))
        }
        UIColor.black.set()
        fill.lineWidth = 0
        fill.fill()
        UIColor(white: 0.5, alpha: 1).set()
        trend.lineWidth = 0
        trend.fill()

        let syringeImage = UIImage(named: "syringe", in: Bundle(for: type(of:self)), compatibleWith: nil)!
        let syringeSize = syringeImage.size
        let mealImage = UIImage(named: "meal", in: Bundle(for: type(of:self)), compatibleWith: nil)!
        let mealSize = mealImage.size
        let c = UIColor.blue.darker(by: 40)
        c.setStroke()
        touchables = []
        for r in records {
            let v = findValue(at: r.date)
            let above = CGFloat(v) < (yRange.max + yRange.min) / 2
            let x = xCoor(r.date)
            var y = above ? 8 : size.height - 8
            if r.isBolus {
                let units = r.bolus
                let center = CGPoint(x: x, y: y + (above ? syringeSize.height / 2 : -syringeSize.height / 2))
                syringeImage.fill(at: center, with: c)
                let iob = r.insulinAction(at: Date()).iob
                let text = "\(units) \(iob > 0 ? "(\(iob.formatted(with: "%.1lf")))" : "")".styled.systemFont(size: 14).color(.darkGray)
                text.draw(at: CGPoint(x: x + syringeSize.width / 2, y: center.y - 2))
                touchables.append((CGRect(center: center, size: syringeSize), r))
                y += above ? syringeSize.height + 4 : -syringeSize.height - 4
            }
            if r.isMeal {
                let center = CGPoint(x: x, y: y + (above ? mealSize.height / 2 : -mealSize.height / 2))
                mealImage.fill(at: center, with: c)
                touchables.append((CGRect(center: center, size: mealSize), r))
                y += above ? mealSize.height + 4 : -mealSize.height - 4
            }
            ctx?.beginPath()
            ctx?.move(to: CGPoint(x: x, y: y))
            ctx?.addLine(to: CGPoint(x: x, y: yCoor(CGFloat(v)) + (above ? -10 : 10)))
            ctx?.strokePath()
        }

        if let touchPoint = touchPoint {
            let coor = CGPoint(x: xCoor(touchPoint.date), y: yCoor(CGFloat(touchPoint.value)))
            UIColor.darkGray.set()
            let IOB = Storage.default.allEntries.filter { $0.date > touchPoint.date - (defaults[.diaMinutes] + defaults[.delayMinutes]) * 60 && $0.date < touchPoint.date }.reduce(0.0) { $0 + $1.insulinAction(at: touchPoint.date).iob }
            ctx?.beginPath()
            ctx?.move(to: CGPoint(x: rect.width, y: coor.y))
            ctx?.addLine(to: coor)
            if IOB > 0 {
                ctx?.addLine(to: CGPoint(x: coor.x, y: rect.height - 40))
                ctx?.move(to: CGPoint(x: coor.x, y: rect.height - 20))
            }
            ctx?.addLine(to: CGPoint(x: coor.x, y: rect.height))
            ctx?.strokePath()
            if IOB > 0 {
                let text = "IOB=\(IOB.formatted(with: "%.1lf"))".styled.font(UIFont.systemFont(ofSize: 15))
                let size = text.size()
                var rect = CGRect(center: CGPoint(x: coor.x, y: rect.height - 30), size: size)
                if rect.maxX > contentView.bounds.maxX {
                    rect.origin.x = contentView.bounds.maxX - size.width
                }
                text.draw(in: rect)
            }
        }
    }

    private func findValue(at: Date) -> Double {
        return points.reduce((Double(0), 24.h)) { abs($1.date - at) < $0.1 ? ($1.value, abs($1.date - at)) : $0 }.0
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
        let xScale = rect.size.width / CGFloat(xRange.max - xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - self.xRange.min) * xScale }
        ctx?.strokePath()

        var touchLabelFrame: CGRect?
        if let touchPoint = touchPoint {
            let c =  UIColor.blue.darker(by: 70)
            let str = String(format: "%02ld:%02ld", touchPoint.date.hour, touchPoint.date.minute).styled.systemFont(.bold, size: 14).color(c.darker(by: 50))
            let size = str.size()
            var p = CGPoint(x: xCoor(touchPoint.date) - size.width / 2, y: 3)
            if p.x + size.width > rect.width {
                p.x = rect.width - size.width
            }
            touchLabelFrame = CGRect(origin: p, size: size)
            if touchLabelFrame!.maxY > rect.maxY {
                touchLabelFrame = CGRect(origin: CGPoint(x: rect.width - size.width, y: 3), size: size)
            }
            str.draw(in: touchLabelFrame!)
        }

        var components = xRange.min.components
        components.second = 0
        components.minute = 0
        var xDate = components.toDate()
        let step: TimeInterval
        if xTimeSpan < 3.h {
            step = 30.m
        } else if xTimeSpan < 7.h {
            step = 1.h
        } else if xTimeSpan < 13.h {
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
        } while xDate < xRange.max
    }

    private func drawYAxis(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()
        let size = contentView.bounds.size
        let yScale = size.height / (yRange.max - yRange.min)
        let yCoor = { (y: Int) in (self.yRange.max - CGFloat(y)) * yScale }

        backgroundColor?.set()
        ctx?.fill(rect)

        UIColor.black.set()
        ctx?.beginPath()
        ctx?.move(to: CGPoint(x: 0, y: 0))
        ctx?.addLine(to: CGPoint(x: 0, y: size.height))
        ctx?.strokePath()

        let touchLabelFrame: CGRect?
        if let touchPoint = touchPoint {
            let v = Int(round(touchPoint.value))
            let c =  UIColor.blue.darker(by: 70)
            let str = "\(v)".styled.systemFont(.bold, size: 14).color(c.darker(by: 50))
            let size = str.size()
            touchLabelFrame = CGRect(origin: CGPoint(x: 3, y: yCoor(v) - size.height / 2), size: size)
            str.draw(in: touchLabelFrame!)
        } else {
            touchLabelFrame = nil
        }

        for y in yReference {
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
        contentView = DrawingView { [weak self] (rect) in
            self?.drawContent(rect)
        }
        contentView.backgroundColor = .clear

        if isScrollEnabled {
            contentHolder = UIScrollView(frame: .zero)
            contentHolder.translatesAutoresizingMaskIntoConstraints = false
            addSubview(contentHolder)
            contentHolder.delegate = self
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
        } else {
            addSubview(contentView)
            makeConstraints {
                contentView[.top] == self[.top]
                contentView[.left] == self[.left]
                contentView[.right] == self[.right] - 40
                contentView[.height] == self[.height] - xAxisHeight
            }
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
        xAxis.backgroundColor = .clear
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
        yAxis.backgroundColor = .clear
        addSubview(yAxis)
        makeConstraints {
            yAxis[.top] == self.contentHolder[.top]
            yAxis[.left] == self.contentHolder[.right]
            yAxis[.bottom] == self[.bottom]
            yAxis[.right] == self[.right]
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        contentView.addGestureRecognizer(doubleTap)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        contentView.setNeedsDisplay()
        xAxis.setNeedsDisplay()
        yAxis.setNeedsDisplay()
    }

    private var touchPoint: GlucoseReading? {
        didSet {
            contentView.setNeedsDisplay()
            xAxis.setNeedsDisplay()
            yAxis.setNeedsDisplay()
        }
    }

    @objc private func handleDoubleTap(_ sender: UIGestureRecognizer) {
        let touchPoint = sender.location(in: contentView)
        self.prediction = nil

        for touchable in touchables {
            if touchable.0.contains(touchPoint) {
                delegate?.didDoubleTap(record: touchable.1)
                return
            }
        }
    }
    @objc private func handleTap(_ sender: UIGestureRecognizer) {
        let touchPoint = sender.location(in: contentView)

        for touchable in touchables {
            if touchable.0.contains(touchPoint) {
                prediction = nil
                delegate?.didTouch(record: touchable.1)
                return
            }
        }
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
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        xAxisHolder.contentOffset = scrollView.contentOffset
        if touchPoint != nil {
            touchPoint = nil
        }
    }
}

extension GlucoseGraph {

    override public func prepareForInterfaceBuilder() {
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


extension UIImage {
    func fill(at: CGPoint, with color: UIColor) {
        let imageRect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context!.translateBy(x: 0, y: size.height)
        context!.scaleBy(x: 1.0, y: -1.0)
        context!.setBlendMode(CGBlendMode.multiply)
        context!.clip(to: imageRect, mask: cgImage!)
        color.setFill()
        context!.fill(imageRect)
        context?.restoreGState()
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        out?.draw(in: CGRect(origin: CGPoint(x: at.x - size.width / 2, y: at.y - size.height / 2), size: size))
    }
}
