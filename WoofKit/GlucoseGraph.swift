//
//  GlucoseGraph.swift
//
//
//  Created by Guy on 27/12/2018.
//

import UIKit
import CoreGraphics
import SwiftUI

public protocol GlucoseGraphDelegate: class {
    func didTouch(record: Record)
    func didDoubleTap(record: Record)
}

extension GlucoseGraphDelegate {
    public func didDoubleTap(record: Record) { }
}

private let contractionFactor = CGFloat(0.6)

public let DeletedPointsNotification = Notification.Name("deleted points")
public let WillDeletePointsNotification = Notification.Name("will delete points")

public struct Prediction {
    public let highDate: Date
    public let h10: CGFloat
    public let h50: CGFloat
    public let h90: CGFloat
    public let mealTime: Date
    public let low50: CGFloat
    public let low: CGFloat
    public let mealCount: Int

    public init(count: Int, mealTime: Date, highDate: Date, h10: CGFloat, h50: CGFloat, h90: CGFloat, low50: CGFloat,  low: CGFloat) {
        self.highDate = highDate
        self.h10 = h10
        self.h50 = h50
        self.h90 = h90
        self.mealTime = mealTime
        self.low = low
        self.low50 = low50
        mealCount = count
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
    @IBInspectable var isScrollEnabled:Bool
    @IBInspectable public var enableDelete: Bool = false {
        didSet {
            if enableDelete && contentView != nil {
                let long = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
                long.delegate = self
                contentView.addGestureRecognizer(long)
            }
        }
    }
    @IBInspectable public var showAverage: Bool = false {
        didSet {
            setNeedsDisplay()
        }
    }
    private var averageValue: CGFloat = 0

    public var points: [GlucoseReading]! {
        didSet {
            guard !points.isEmpty else {
                return
            }
            if points.last!.date < points.first!.date {
                 points = points.reversed()
            }
            
            let (gmin, gmax) = points.reduce((999.0, 0.0)) { (min($0.0, $1.value), max($0.1, $1.value)) }
            segments = []
            var segmentStart = 0
            trendIsMarked = false
            if points.count > 1 {
                for (idx, gp) in points[1...].enumerated() {
                    if gp.type == .calibration {
                        segments.append(segmentStart...idx)
                        segmentStart = idx + 1
                    } else if gp.date - points[idx].date > 1.h + 30.m {
                        segments.append(segmentStart...idx)
                        segmentStart = idx + 1
                    }
                    if gp.type == .trend {
                        trendIsMarked = true
                    }
                }
            }
            segments.append(segmentStart...(points.count - 1))
            yRange.min = max(CGFloat(floor(gmin / 5) * 5), 10)
            yRange.max = max(CGFloat(ceil(gmax / 5) * 5), CGFloat(ceil((prediction?.h50 ?? 0) / 5) * 5))
            contentWidthConstraint?.isActive = false
            if isScrollEnabled {
                contentWidthConstraint = (contentView[.width] == self[.width] * CGFloat((xRange.max - xRange.min) / xTimeSpan))
            }
            setNeedsLayout()
            if showAverage {
                let zipped = zip(points[0 ..< points.count - 1], points[1 ..< points.count])
                averageValue = CGFloat(zipped.map { ($0.1.date - $0.0.date) * ($0.0.value + $0.1.value) }.sum() / (points.last!.date - points.first!.date) / 2.0)
            }
            DispatchQueue.main.async {
                if let holder = self.contentHolder, !holder.isDragging && !holder.isDecelerating {
                    holder.contentOffset = CGPoint(x: self.contentHolder.contentSize.width - self.contentHolder.width, y: 0)
                }
            }
        }
    }
    private var segments: [ClosedRange<Int>] = []
    public var yRange = (min: CGFloat(70), max: CGFloat(180))
    public var xRange = (min: Date() - 1.d, max: Date())
    public var lineWidth: CGFloat = 1.5
    public var dotRadius: CGFloat = 3
    public var xTimeSpan = 6.h {
        didSet {
            if isScrollEnabled {
                contentWidthConstraint?.isActive = false
                contentWidthConstraint = (contentView[.width] == self[.width] * CGFloat((xRange.max - xRange.min) / xTimeSpan))
                setNeedsLayout()
            }
            setNeedsDisplay()
        }
    }
    public var records: [Record] = [] {
        didSet {
            contentView.setNeedsDisplay()
        }
    }
    public var prediction: Prediction? {
        didSet {
            let h = CGFloat(ceil((prediction?.h50 ?? 0) / 5) * 5)
            if h > yRange.max {
                yRange.max = h
            }
            contentView.setNeedsDisplay()
        }
    }
    public var pattern: Pattern? {
        didSet {
            contentView.setNeedsDisplay()
        }
    }
    public var manual: [ManualMeasurement]? {
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
    
    private var theme: UIUserInterfaceStyle {
        return traitCollection.userInterfaceStyle
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            setNeedsDisplay()
        }
    }
    override public func layoutSubviews() {
        super.layoutSubviews()
        contentView.setNeedsDisplay()
        xAxis.setNeedsDisplay()
        yAxis.setNeedsDisplay()
    }
    
    public override func setNeedsDisplay() {
        super.setNeedsDisplay()
        if contentView != nil {
            contentView.setNeedsDisplay()
            xAxis.setNeedsDisplay()
            yAxis.setNeedsDisplay()
        }
    }
    
    public override func setNeedsLayout() {
        super.setNeedsLayout()
        if contentView != nil {
            contentView.setNeedsDisplay()
            xAxis.setNeedsDisplay()
            yAxis.setNeedsDisplay()
        }
    }
    
    private var trendIsMarked = false
    
    private func drawContent(_ rect: CGRect) {
        let colors = [(defaults[.level0], defaults[.color0]),
                      (defaults[.level1], defaults[.color1]),
                      (defaults[.level2], defaults[.color2]),
                      (defaults[.level3], defaults[.color3]),
                      (defaults[.level4], defaults[.color4]),
                      (999.0, defaults[.color5])]
        guard self.points != nil, !points.isEmpty else {
            return
        }
        let ctx = UIGraphicsGetCurrentContext()
        let size = contentView.bounds.size
        
        UIColor.red.set()
        ctx?.fill(rect)
        
        let yScale = size.height / (yRange.max - yRange.min)
        let yCoor = { (self.yRange.max - $0) * yScale }
        let xScale = rect.size.width / CGFloat(xRange.max - xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - self.xRange.min) * xScale }
        var lower:Double = 0
        for (upper, color) in colors {
            if theme == .dark {
                color.darker(by: 60).set()
            } else {
                color.set()
            }
            let r = CGRect(x: 0.0, y: yCoor(CGFloat(upper)), width: size.width, height: CGFloat(upper - lower) * yScale)
            ctx?.fill(r)
            lower = upper
        }
        ctx?.beginPath()
        if theme != .dark {
            UIColor(white: 0.25, alpha: 0.5).set()
        } else {
            UIColor(white: 0.5, alpha: 1).set()
        }
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

        drawPrediction: if let prediction = prediction {
//            guard Storage.default.allEntries.filter({ $0.date > prediction.mealTime && $0.date < prediction.highDate }).isEmpty else {
//                self.prediction = nil
//                break drawPrediction
//            }
            let duration = prediction.mealCount == 0 ? 20.m : 30.m
            ctx?.saveGState()
            ctx?.setLineWidth(3)
            ctx?.saveGState()
            ctx?.beginPath()
            UIColor.blue.withAlphaComponent(0.4).set()
            ctx?.setLineDash(phase: 0, lengths: [2,8])
            if prediction.h90 > 0 {
            ctx?.move(to: CGPoint(x: xCoor(prediction.mealTime), y: yCoor(prediction.h90)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate - duration), y: yCoor(prediction.h90)))
            ctx?.move(to: CGPoint(x: xCoor(prediction.mealTime), y: yCoor(prediction.h10)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate - duration), y: yCoor(prediction.h10)))
            }
            ctx?.move(to: CGPoint(x: xCoor(prediction.mealTime), y: yCoor(prediction.h50)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate - duration), y: yCoor(prediction.h50)))
            ctx?.strokePath()
            if prediction.low > 30 && prediction.low50 > 30 {
                ctx?.beginPath()
                UIColor.blue.withAlphaComponent(0.6).set()
                ctx?.setLineDash(phase: 0, lengths: [4,14])
                ctx?.move(to: CGPoint(x: xCoor(prediction.highDate), y: yCoor(prediction.low)))
                ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate + 5.h), y: yCoor(prediction.low)))
                ctx?.move(to: CGPoint(x: xCoor(prediction.highDate), y: yCoor(prediction.low50)))
                ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate + 5.h), y: yCoor(prediction.low50)))
                ctx?.strokePath()
                do {
                    let postfix = prediction.mealCount == 0 ? "1σ = " : ""
                    let text = "\(Int(round(prediction.low)))\(postfix)".styled.systemFont(size: 14).color(.blue)
                    let size = text.size()
                    text.draw(in: CGRect(x: xCoor(prediction.highDate), y: yCoor(prediction.low) - size.height, width: size.width, height: size.height))
                }
                do {
                    let prefix = prediction.mealCount == 0 ? "Ave " : "50% = "
                    let text = "\(prefix)\(Int(round(prediction.low50)))".styled.systemFont(size: 14).color(.blue)
                    let size = text.size()
                    text.draw(in: CGRect(x: xCoor(prediction.highDate), y: yCoor(prediction.low50) - size.height, width: size.width, height: size.height))
                }
            }
            ctx?.restoreGState()
            if prediction.h90 > prediction.h50 {
                let prefix = prediction.mealCount == 0 ? "80% < " : "90% < "
                let text = "\(prefix)\(Int(round(prediction.h90)))".styled.systemFont(size: 14).color(.blue)
                let size = text.size()
                text.draw(in: CGRect(x: xCoor(prediction.highDate - duration), y: yCoor(prediction.h90) - size.height, width: size.width, height: size.height))
            }
            if prediction.h10 < prediction.h50 && prediction.h10 > 0 {
                let prefix = prediction.mealCount == 0 ? "80% < " : "90% > "
                let text = "\(prefix)\(Int(round(prediction.h10)))".styled.systemFont(size: 14).color(.blue)
                let size = text.size()
                text.draw(in: CGRect(x: xCoor(prediction.highDate - duration), y: yCoor(prediction.h10) - size.height, width: size.width, height: size.height))
            }
            do {
                let prefix = prediction.mealCount > 2 ? "50% = " : ""
                let text = "\(prefix)\(Int(round(prediction.h50)))".styled.systemFont(size: 14).color(.blue)
                let size = text.size()
                text.draw(in: CGRect(x: xCoor(prediction.highDate - duration), y: yCoor(prediction.h50) - size.height, width: size.width, height: size.height))
            }
            ctx?.saveGState()
            ctx?.beginPath()
            UIColor.blue.withAlphaComponent(0.6).set()
            ctx?.setLineDash(phase: 0, lengths: [4,3])
            ctx?.move(to: CGPoint(x: xCoor(prediction.highDate - duration), y: yCoor(prediction.h50)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate + duration), y: yCoor(prediction.h50)))
            ctx?.strokePath()
            ctx?.restoreGState()
            ctx?.saveGState()
            ctx?.beginPath()
            UIColor.blue.withAlphaComponent(0.4).set()
            ctx?.setLineDash(phase: 0, lengths: prediction.mealCount == 0 ? [3,3] : [6,4])
            ctx?.move(to: CGPoint(x: xCoor(prediction.highDate - duration), y: yCoor(prediction.h90)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate + duration), y: yCoor(prediction.h90)))
            ctx?.move(to: CGPoint(x: xCoor(prediction.highDate - duration), y: yCoor(prediction.h10)))
            ctx?.addLine(to: CGPoint(x: xCoor(prediction.highDate + duration), y: yCoor(prediction.h10)))
            ctx?.strokePath()
            ctx?.restoreGState()
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
        let all = points.map { CGPoint(x: xCoor($0.date), y: yCoor(CGFloat($0.value))) }
        let calibrationPoints = points.filter( { $0.type == .calibration }).map { CGPoint(x: xCoor($0.date), y: yCoor(CGFloat($0.value))) }
        let plotter = Plot(points: all)
        if showAverage {
            ctx?.saveGState()
            ctx?.setLineDash(phase: 0, lengths: [2,2,2,8])
            ctx?.move(to: CGPoint(x: 0, y: yCoor(averageValue)))
            ctx?.addLine(to: CGPoint(x: rect.width, y: yCoor(averageValue)))
            UIColor.darkGray.set()
            ctx?.setAlpha(0.75)
            ctx?.strokePath()
            let text = "\(averageValue % ".0lf")".styled.color(.darkGray).systemFont(.semibold, size: 17)
            let size = text.size()
            var frame = CGRect(x: rect.width - size.width - 8, y: yCoor(averageValue) - 1 - size.height, width: size.width, height: size.height)
            while plotter.intersects(frame) {
                frame.origin.x -= 8
            }
            text.draw(in: frame)
            ctx?.restoreGState()
        }
        if theme == .dark {
            plotter.set(colors: colors.map { (yCoor(CGFloat($0.0)), $0.1) })
            var curves = [(UIColor, UIBezierPath)]()
            for x in segments {
                curves += plotter.coloredLines(from: all[x.lowerBound].x , to: all[x.upperBound].x )
            }
            for (color,path) in curves {
                color.set()
                path.lineWidth = lineWidth
                path.stroke()
            }
            for idx in 0 ..< points.count {
                let point = all[idx]
                let trend = trendIsMarked ? points[idx].type == .trend : points.last!.date - points[idx].date < 15.m
                let r = trend ? dotRadius - 1 : dotRadius
                plotter.colorForValue(point.y).set()
                UIBezierPath(ovalIn: CGRect(origin: point - CGPoint(x: r, y: r), size: CGSize(width: 2 * r, height: 2 * r))).fill()
            }
        } else {
            do1: do {
                if all.isEmpty {
                    break do1
                }
                let curve = UIBezierPath()
              
                for segment in segments {
                    curve.append(plotter.line(from: all[segment.lowerBound].x, to: all[max(segment.upperBound,all.count - 1)].x))
                }
                    
                UIColor.darkGray.set()
                curve.lineWidth = lineWidth
                curve.stroke()
                let fill = UIBezierPath()
                let dotSize = CGSize(width: 2 * dotRadius, height: 2 * dotRadius)
                let trendDotSize = CGSize(width: 2 * dotRadius - 1, height: 2 * dotRadius - 1)

                for idx in 0 ..< all.count {
                    let point = all[idx]
                    let trend = trendIsMarked ? points[idx].type == .trend : points.last!.date - points[idx].date < 15.m
                    fill.append(UIBezierPath(ovalIn: CGRect(center: point, size: trend ? trendDotSize : dotSize)))
                }
                UIColor.label.set()
                fill.lineWidth = 0
                fill.fill()
            }
            
            UIColor.label.set()
            ctx?.setLineWidth(0.5)
            for point in calibrationPoints {
                ctx?.addEllipse(in: CGRect(center: point, size: CGSize(width: 14, height: 14)))
            }
            ctx?.strokePath()
        }
        if !pointsToDelete.isEmpty {
            let selected = UIBezierPath()
            for idx in pointsToDelete {
                let point = all[idx]
                selected.append(UIBezierPath(ovalIn: CGRect(center: point, size: CGSize(width: 20, height: 20))))
            }
            UIColor.magenta.set()
            selected.stroke()
        }

        let syringeImage = UIImage(named: "syringe", in: Bundle(for: type(of:self)), compatibleWith: nil)!
        let syringeSize = syringeImage.size
        let mealImage = UIImage(named: "meal", in: Bundle(for: type(of:self)), compatibleWith: nil)!
        let mealSize = mealImage.size
        let c = UIColor.secondaryLabel.withAlphaComponent(0.75)
        c.setStroke()
        touchables = []
        for r in records {
            let x = xCoor(r.date)
            let v = plotter.value(at: x)
            let above = v > contentView.bounds.height / 2
            let positions: [CGFloat]
            if above {
                positions = (v - [80.0,100.0,120.0,150.0,180.0,200.0,250.0,300.0,350.0]).filter { $0 > 8 } + [8.0]
            } else {
                positions = (v + [80.0,100.0,120.0,150.0,180.0,200.0,250.0,300.0,350.0]).filter { $0 < size.height - 8 } + [size.height - 8]
            }
            for position in positions {
                if position == positions[0] && r.isMeal {
                    continue
                }
                let isLast = (position == positions.last!)
                var y = position
                var drawers = [()->Void]()
                if r.isBolus {
                    let units = r.bolus
                    let center = CGPoint(x: x, y: y + (above ? syringeSize.height / 2 : -syringeSize.height / 2))
                    let frame = CGRect(center: center, size: syringeSize + CGSize(width: 4, height: 4))
                    let iob = r.insulinAction(at: Date()).iob
                    let text = "\(units) \(iob > 0 ? "(\(iob % ".1lf"))" : "")".styled.systemFont(size: 14).color(UIColor.tertiaryLabel.withAlphaComponent(0.75))
                    let textFrame = CGRect(origin: CGPoint(x: x + syringeSize.width / 2, y: center.y - 2), size: text.size())
                    if (plotter.intersects(frame) || plotter.intersects(textFrame)) && !isLast {
                        continue
                    } else {
                        drawers.append {
                            syringeImage.fill(at: center, with: c)
                            text.draw(in: textFrame)
                            self.touchables.append((CGRect(center: center, size: syringeSize), r))
                        }
                    }
                    y += above ? syringeSize.height + 4 : -syringeSize.height - 4
                }
                if r.isMeal {
                    let center = CGPoint(x: x, y: y + (above ? mealSize.height / 2 : -mealSize.height / 2))
                    let frame = CGRect(center: center, size: mealSize + CGSize(width: 4, height: 4))
                    if plotter.intersects(frame) && !isLast {
                        continue
                    } else {
                        drawers.append {
                            mealImage.fill(at: center, with: c)
                            self.touchables.append((CGRect(center: center, size: mealSize), r))
                        }
                    }
                    y += above ? mealSize.height + 4 : -mealSize.height - 4
                    let note = r.note ?? ""
                    let text = (r.carbs > 0 ? "\(note)\(note.isEmpty ? "" : ": ")\(r.carbs % ".0lf")" : note).styled.systemFont(size: 14).color(UIColor.tertiaryLabel.withAlphaComponent(0.75))
                    let size = text.size()
                    let r1 = CGRect(x: center.x + mealSize.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
                    let check = r1.insetBy(dx: -6, dy: -6)
                    if plotter.intersects(check) {
                        let r2 = CGRect(x: center.x - mealSize.width / 2 - size.width, y: center.y - size.height / 2, width: size.width, height: size.height)
                        let check = r2.insetBy(dx: -6, dy: -6)
                        if  plotter.intersects(check) {
                            if isLast {
                                drawers.append {
                                    text.draw(in: r1)
                                }
                            } else {
                                continue
                            }
                        } else {
                            drawers.append {
                                text.draw(in: r2)
                            }
                        }
                    } else {
                        drawers.append {
                            text.draw(in: r1)
                        }
                    }
                }
                drawers.forEach { $0() }
                ctx?.beginPath()
                ctx?.move(to: CGPoint(x: x, y: y))
                ctx?.addLine(to: CGPoint(x: x, y: v + (above ? -3 : 3)))
                ctx?.strokePath()
                break
            }
        }

        if let manual = manual {
            UIColor {
                switch $0.userInterfaceStyle {
                case .unspecified:
                    return #colorLiteral(red: 0.5725490451, green: 0, blue: 0.2313725501, alpha: 1)
                case .light:
                    return #colorLiteral(red: 0.4347818196, green: 0.1882995963, blue: 0.8658901453, alpha: 1)
                case .dark:
                    return #colorLiteral(red: 0.6591138715, green: 0.445930695, blue: 1, alpha: 1)
                @unknown default:
                    return #colorLiteral(red: 0.9254902005, green: 0.2352941185, blue: 0.1019607857, alpha: 1)
                }
            }.set()
            let path = UIBezierPath()
            path.lineWidth = 2
            manual.map { CGPoint(x: xCoor($0.date), y: yCoor(CGFloat($0.value))) }.forEach {
                path.append(UIBezierPath(roundedRect: CGRect(center: $0, size: CGSize(width: 9, height: 8)), cornerRadius: 2))
            }
            path.stroke()
        }

        if let touchPoint = touchPoint {
            let coor = CGPoint(x: xCoor(touchPoint.date), y: yCoor(CGFloat(touchPoint.value)))
            UIColor.tertiaryLabel.set()
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
                let text = "BOB=\(IOB % ".1lf")".styled.font(UIFont.systemFont(ofSize: 15)).color(UIColor.tertiaryLabel)
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
        if #available(iOSApplicationExtension 13.0, *) {
            UIColor.label.set()
        } else {
            UIColor.black.set()
        }
        ctx?.setLineWidth(1)
        ctx?.beginPath()
        ctx?.move(to: CGPoint(x: 0, y: 0))
        ctx?.addLine(to: CGPoint(x: rect.width, y: 0))
        let xScale = rect.size.width / CGFloat(xRange.max - xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - self.xRange.min) * xScale }
        ctx?.strokePath()

        var touchLabelFrame: CGRect?
        if let touchPoint = touchPoint {
            let c: UIColor
            if #available(iOSApplicationExtension 13.0, *) {
                c = UIColor.label
            } else {
                c =  UIColor.blue.darker(by: 80)
            }
            let str = String(format: "%02ld:%02ld", touchPoint.date.hour, touchPoint.date.minute).styled.systemFont(.bold, size: 14).color(c)
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
            if #available(iOSApplicationExtension 13.0, *) {
                UIColor.secondaryLabel.set()
            } else {
                UIColor.black.set()
            }
            ctx?.beginPath()
            ctx?.move(to: CGPoint(x: xCoor(xDate), y: 0))
            ctx?.addLine(to: CGPoint(x: xCoor(xDate), y: 5))
            let tick = xCoor(xDate + step / 2)
            ctx?.move(to: CGPoint(x: tick, y: 0))
            ctx?.addLine(to: CGPoint(x: tick, y: 3))
            ctx?.strokePath()
            let str: NSAttributedString
            if #available(iOSApplicationExtension 13.0, *) {
                str = String(format: "%02ld:%02ld", xDate.hour, xDate.minute).styled.systemFont(size: 14).color(.label)
            } else {
                str = String(format: "%02ld:%02ld", xDate.hour, xDate.minute).styled.systemFont(size: 14)
            }
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

        if #available(iOSApplicationExtension 13.0, *) {
            UIColor.label.set()
        } else {
            UIColor.black.set()
        }
        ctx?.beginPath()
        ctx?.move(to: CGPoint(x: 0, y: 0))
        ctx?.addLine(to: CGPoint(x: 0, y: size.height))
        ctx?.strokePath()

        let touchLabelFrame: CGRect?
        if let touchPoint = touchPoint {
            let v = Int(round(touchPoint.value))
            let c: UIColor
            if #available(iOSApplicationExtension 13.0, *) {
                c =  UIColor.label
            } else {
                c =  UIColor.blue.darker(by: 80)
            }
            let str = "\(v)".styled.systemFont(.bold, size: 14).color(c)
            let size = str.size()
            touchLabelFrame = CGRect(origin: CGPoint(x: 3, y: yCoor(v) - size.height / 2), size: size)
            str.draw(in: touchLabelFrame!)
        } else {
            touchLabelFrame = nil
        }

        if #available(iOSApplicationExtension 13.0, *) {
            UIColor.secondaryLabel.set()
        } else {
            // Fallback on earlier versions
        }
        for y in yReference {
            if CGFloat(y) < self.yRange.min || CGFloat(y) > self.yRange.max {
                continue
            }
            ctx?.beginPath()
            ctx?.move(to: CGPoint(x: 0, y: yCoor(y)))
            ctx?.addLine(to: CGPoint(x: 5, y: yCoor(y)))
            ctx?.strokePath()
            let label: NSMutableAttributedString
            if #available(iOSApplicationExtension 13.0, *) {
                label = "\(y)".styled.systemFont(size: 14).color(.label)
            } else {
                label = "\(y)".styled.systemFont(size: 14)
            }
            let size = label.size()
            let labelFrame = CGRect(origin: CGPoint(x: 6, y: yCoor(y) - size.height / 2), size: size)
            if rect.contains(labelFrame) && (touchLabelFrame == nil || !touchLabelFrame!.intersects(labelFrame)) {
                label.draw(in: labelFrame)
            }
        }
    }

    public func scroll(to date: Date) {
        let scrollTo = max(min(date - xTimeSpan / 2, xRange.max), xRange.min)
        let w = contentView.bounds.width
        let offset = (scrollTo - xRange.min) / (xRange.max - xRange.min) * Double(w)
        contentHolder.contentOffset = CGPoint(x: offset, y: 0)
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
                contentView[.bottom] == self[.bottom] - xAxisHeight
            }
        }
        
        if isScrollEnabled {
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
        }
        
        xAxis = DrawingView { [weak self] (rect) in
            self?.drawXAxis(rect)
        }
        xAxis.backgroundColor = .clear
        if isScrollEnabled {
            xAxisHolder.addSubview(xAxis)
            makeConstraints {
                xAxis[.top] == xAxisHolder[.top]
                xAxis[.bottom] == xAxisHolder[.bottom]
                xAxis[.left] == xAxisHolder[.left]
                xAxis[.right] == xAxisHolder[.right]
                xAxis[.height] == xAxisHeight
                xAxis[.width] == contentView[.width]
            }
        } else {
            self.addSubview(xAxis)
            makeConstraints {
                xAxis[.bottom] == self[.bottom]
                xAxis[.left] == self[.left]
                xAxis[.height] == xAxisHeight
                xAxis[.width] == contentView[.width]
            }
            
        }
        
        yAxis = DrawingView { [weak self] (rect) in
            self?.drawYAxis(rect)
        }
        yAxis.backgroundColor = .clear
        addSubview(yAxis)
        makeConstraints {
            if isScrollEnabled {
                yAxis[.left] == self.contentHolder[.right]
            } else {
                yAxis[.left] == self.contentView[.right]
            }
            yAxis[.width] == 40
            yAxis[.top] == self[.top]
            yAxis[.bottom] == self[.bottom]
            yAxis[.right] == self[.right]
        }
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        contentView.addGestureRecognizer(doubleTap)
        
        if enableDelete {
            let long = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
            long.delegate = self
            contentView.addGestureRecognizer(long)
        }
    }

    init(frame: CGRect, withScrolling: Bool = true) {
        isScrollEnabled = withScrolling
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        isScrollEnabled = true
        super.init(coder: aDecoder)
    }
    
    public override func awakeFromNib() {
        super.awakeFromNib()
        commonInit()
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

    private var pointsToDelete = Set<Int>() {
        didSet {
            contentView.setNeedsDisplay()
        }
    }
    @objc private func longPress(_ sender: UILongPressGestureRecognizer) {
        switch sender.state {
        case .began, .changed:
            let yScale = contentView.bounds.size.height / (yRange.max - yRange.min)
            let yCoor = { (self.yRange.max - $0) * yScale }
            let xScale = contentView.bounds.size.width / CGFloat(xRange.max - xRange.min)
            let xCoor = { (d: Date) in CGFloat(d - self.xRange.min) * xScale }
            let touchPoint = sender.location(in: contentView)
            let historyPoints = points.enumerated().filter { $0.element.type != .trend }.map { (offset: $0.offset, element: CGPoint(x: xCoor($0.element.date), y: yCoor(CGFloat($0.element.value)))) }
            let nearest = historyPoints.filter { abs(touchPoint.x - $0.element.x) < 40 && abs(touchPoint.y - $0.element.y) < 40 }.map { (offset: $0.offset, element: touchPoint.distance(to: $0.element)) }.sorted(by: { $0.element < $1.element }).first?.offset
            if let nearest = nearest, !pointsToDelete.contains(nearest) {
                pointsToDelete.insert(nearest)
                let impacter = UIImpactFeedbackGenerator()
                impacter.impactOccurred()
            }


        case .ended:
            if !pointsToDelete.isEmpty {
                let sheet = UIAlertController(title: "Delete point\(pointsToDelete.count > 1 ? "s" : "")?", message: "Really delete the selected point\(pointsToDelete.count > 1 ? "s" : "")?", preferredStyle: .actionSheet)
                sheet.addAction(UIAlertAction(title: "Delete", style: .default, handler: { (_) in
                    NotificationCenter.default.post(name: WillDeletePointsNotification, object: self)
                    if var changedPoints = self.points {
                        for selected in Array(self.pointsToDelete).sorted().reversed() {
                            changedPoints.remove(at: selected)
                            let date = self.points[selected].date
                            try? Storage.default.db.execute("delete from \(GlucosePoint.tableName) where \(GlucosePoint.date.name) > \((date - 1.m).timeIntervalSince1970) and \(GlucosePoint.date.name) < \((date + 1.m).timeIntervalSince1970)")
                        }
//                        let offset = self.contentHolder.contentOffset
                        NotificationCenter.default.post(name: DeletedPointsNotification, object: self)
                        self.points = changedPoints
                        self.pointsToDelete = []
                        self.setNeedsDisplay()
//                        DispatchQueue.main.async {
//                            self.contentHolder.contentOffset = offset
//                        }
                    }
                }))
                sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in
                    self.pointsToDelete = []
                }))
                controller?.present(sheet, animated: true, completion: nil)
            }

        default:
            break
        }
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

extension GlucoseGraph: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard points != nil else {
            return false
        }
        let yScale = contentView.bounds.size.height / (yRange.max - yRange.min)
        let yCoor = { (self.yRange.max - $0) * yScale }
        let xScale = contentView.bounds.size.width / CGFloat(xRange.max - xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - self.xRange.min) * xScale }
        let touchPoint = touch.location(in: contentView)
        let historyPoints = self.points.enumerated().filter { $0.element.type == .history }.map { (offset: $0.offset, element: CGPoint(x: xCoor($0.element.date), y: yCoor(CGFloat($0.element.value)))) }
        let nearest = historyPoints.filter { abs(touchPoint.x - $0.element.x) < 40 && abs(touchPoint.y - $0.element.y) < 40 }.map { (offset: $0.offset, element: touchPoint.distance(to: $0.element)) }
        if let _ = nearest.first {
            return true
        }
        return false
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

public struct GlucoseGraphView: UIViewRepresentable {
    var points: [GlucosePoint]
    var timespan: TimeInterval
    
    public init(points: [GlucosePoint], timespan: TimeInterval) {
        self.points = points
        self.timespan = timespan
    }
    
    public func makeUIView(context: Context) -> GlucoseGraph {
        let uiView = GlucoseGraph(frame: .zero, withScrolling: false)
        uiView.backgroundColor = .clear
        return uiView
    }
    
    public func updateUIView(_ uiView: GlucoseGraph, context: Context) {
        uiView.points = self.points
        uiView.yRange.max = ceil(uiView.yRange.max / 10) * 10
        uiView.yRange.min = floor(uiView.yRange.min / 5) * 5
        if uiView.yRange.max - uiView.yRange.min < 40 {
            let mid = (uiView.yRange.max + uiView.yRange.min) / 2
            uiView.yRange = mid < 90 ? (min: uiView.yRange.min, max: uiView.yRange.min + 40) : (min: mid - 20, max: mid + 20)
        }
        uiView.xRange = (min: points.reduce(Date()) { min($0, $1.date) }, max: Date())
        uiView.xTimeSpan = timespan
    }
}

struct GlucoseGraph_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            GlucoseGraphView(points: [
                GlucosePoint(date: Date() - 1.h, value: 83),
                GlucosePoint(date: Date() - 45.m, value: 95),
                GlucosePoint(date: Date() - 30.m, value: 90),
                GlucosePoint(date: Date() - 15.m, value: 82),
                GlucosePoint(date: Date(), value: 80)
            ], timespan: 2.h)
            .environment(\.colorScheme, .light)
            .background(Color.red)
            .previewLayout(.fixed(width: 300, height: 200))
            
            GlucoseGraphView(points: [
                GlucosePoint(date: Date() - 1.h, value: 83),
                GlucosePoint(date: Date() - 45.m, value: 95),
                GlucosePoint(date: Date() - 30.m, value: 90),
                GlucosePoint(date: Date() - 15.m, value: 82),
                GlucosePoint(date: Date(), value: 80)
            ], timespan: 2.h)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .previewLayout(.fixed(width: 300, height: 200))
        }
    }
}
