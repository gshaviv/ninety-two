//
//  GraphImage.swift
//  woofWatch Extension
//
//  Created by Guy on 19/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import SwiftUI
import WoofKit

struct BGWidgetGraph: View {
    let points: [GlucosePoint]
    let hours: Double
    
    var body: some View {
        GeometryReader { frame in
            if let newImage = BGWidgetGraph.createImage(points: points, size: frame.size, hours: hours) {
                 Image(uiImage: newImage)
            } else {
                 Image(uiImage: UIImage(systemName: "waveform.path.ecg")!)
            }
        }
        
    }
    
    
    
    static func createImage(points: [GlucosePoint], size: CGSize, hours: Double) -> UIImage? {
        let colors = [0 ... defaults[.level0]: defaults[.color0] ,
                      defaults[.level0] ... defaults[.level1]: defaults[.color1] ,
                      defaults[.level1] ... defaults[.level2]: defaults[.color2] ,
                      defaults[.level2] ... defaults[.level3]: defaults[.color3] ,
                      defaults[.level3] ... defaults[.level4]: defaults[.color4] ,
                      defaults[.level4] ... 999: defaults[.color5] ]
        let yReference = [35, 40, 50, 60, 70, 80, 90, 100, 120, 140, 160, 180, 200, 225, 250, 275, 300, 350, 400, 500]
        let lineWidth:CGFloat
        let dotRadius:CGFloat
        let trendRadius:CGFloat
        if defaults[.useDarkGraph] {
            lineWidth = 2
            dotRadius = 4
            trendRadius = 2
        } else {
            lineWidth = 1.5
            dotRadius = 3
            trendRadius = 1.5
        }
        
        let (gmin, gmax) = points.reduce((999.0, 0.0)) { (min($0.0, $1.value), max($0.1, $1.value)) }
        var yRange = (min: CGFloat(floor(gmin / 5) * 5), max: CGFloat(ceil(gmax / 10) * 10))
        if yRange.max - yRange.min < 40 {
            let mid = floor((yRange.max + yRange.min) / 2)
            yRange = mid > 89 ? (min: max(mid - 20, 70), max: max(mid - 20, 70) + 40) : (min: yRange.min, max: yRange.min + 40)
        }
        while let p = points.last?.value, p < Double(yRange.max - yRange.min) * 0.18 + Double(yRange.min) {
            yRange.min -= 5
        }
        let latest = points.reduce(Date.distantPast) { max($0, $1.date) }
        let maxDate = Date() - latest < 5.m ? latest : Date()
        let xRange = (min: maxDate - hours.h, max: maxDate)
        
        UIGraphicsBeginImageContextWithOptions(size, true, 2)
        let ctx = UIGraphicsGetCurrentContext()
        let yScale = size.height / (yRange.max - yRange.min)
        let yCoor = { (yRange.max - $0) * yScale }
        func valueFor(y: CGFloat) -> Double {
            Double(y / yScale + yRange.min)
        }
        let xScale = size.width / CGFloat(xRange.max - xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - xRange.min) * xScale }
        for (range, color) in colors {
            if defaults[.useDarkGraph] {
                color.darker(by: 60).set()
            } else {
                color.set()
            }
            let area = CGRect(x: 0.0, y: floor(yCoor(CGFloat(range.upperBound))), width: size.width, height: ceil(abs(CGFloat(range.upperBound - range.lowerBound) * yScale)))
            ctx?.fill(area)
        }
        ctx?.beginPath()
        func colorForValue(_ v: Double) -> UIColor {
            for (range,color) in colors {
                if range.contains(v) {
                    return color
                }
            }
            return UIColor.black
        }
        
        let clip = UIBezierPath()
        var union = CGRect.zero
        var lastY:CGFloat = 0
        let attrib = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 13, weight: .light),
                      NSAttributedString.Key.foregroundColor: defaults[.useDarkGraph] ? UIColor(white: 0.8, alpha: 1) : UIColor(white: 0.25, alpha: 1)]
        
        for y in yReference.reversed() {
            let yc = yCoor(CGFloat(y))
            let styled = NSAttributedString(string: "\(y)", attributes: attrib)
            let tsize = styled.size()
            let trect = CGRect(origin: CGPoint(x: 4, y: yc - tsize.height / 2), size: tsize)
            if trect.minY > lastY {
                styled.draw(in: trect)
                clip.append(UIBezierPath(rect: trect.inset(by: UIEdgeInsets(top: 0, left: -4, bottom: 0, right: -4))))
                union = union.union(trect)
                lastY = trect.maxY
            }
        }
        
        var components = xRange.min.components
        components.second = 0
        components.minute = 0
        var xDate = components.getDate
        let step = 1.h
        let yplaces = union
        union = union.union(CGRect(origin: .zero, size: size))
        if !defaults[.useDarkGraph] {
            UIColor(white: 0.25, alpha: 0.5).set()
        } else {
            UIColor(white: 0.5, alpha: 1).set()
        }
        repeat {
            let cx = xCoor(xDate)
            let styled = NSAttributedString(string: "\(xDate.hour):00", attributes: attrib)
            let tsize = styled.size()
            let trect = CGRect(origin: CGPoint(x: cx - tsize.width / 2, y: size.height - tsize.height - 2), size: tsize)
            if !yplaces.intersects(trect) {
                styled.draw(in: trect)
                clip.append(UIBezierPath(rect: trect.inset(by: UIEdgeInsets(top: 0, left: -2, bottom: -2, right: -2))))
            }
            xDate += step
        } while xDate < xRange.max
        
        clip.append(UIBezierPath(rect: union))
        clip.usesEvenOddFillRule = true
        ctx?.saveGState()
        clip.addClip()
        components = xRange.min.components
        components.second = 0
        components.minute = 0
        xDate = components.getDate
        repeat {
            ctx?.move(to: CGPoint(x: xCoor(xDate), y: 0))
            ctx?.addLine(to: CGPoint(x: xCoor(xDate), y: size.height))
            xDate += step
        } while xDate < xRange.max
        for y in yReference {
            let yc = yCoor(CGFloat(y))
            ctx?.move(to: CGPoint(x: 0, y: yc))
            ctx?.addLine(to: CGPoint(x: size.width, y: yc))
            ctx?.strokePath()
        }
        ctx?.strokePath()
        ctx?.restoreGState()
        let p = points.map { CGPoint(x: xCoor($0.date), y: CGFloat($0.value)) }
        let pd = points.map { CGPoint(x: xCoor($0.date), y: yCoor(CGFloat($0.value))) }
        if !points.isEmpty {
            if defaults[.useDarkGraph] {
                var curve: UIBezierPath?
                var last = UIColor.black
                let akima = AkimaInterpolator(points: p)
                for x in stride(from: p.first!.x, to: p.last!.x, by: 1) {
                    let value = akima.interpolateValue(at: x)
                    let point = CGPoint(x: x, y: yCoor(value))
                    let current = colorForValue(Double(value))
                    if current != last {
                        if let curve = curve {
                            curve.addLine(to: point)
                            curve.lineWidth = lineWidth
                            last.set()
                            curve.stroke()
                        }
                        curve = UIBezierPath()
                        curve?.move(to: point)
                    } else {
                        curve?.addLine(to: point)
                    }
                    last = current
                }
                if let curve = curve {
                    curve.lineWidth = lineWidth
                    last.set()
                    curve.stroke()
                }
                for gp in points {
                    let point = CGPoint(x: xCoor(gp.date), y: yCoor(CGFloat(gp.value)))
                    colorForValue(gp.value).set()
                    let r = gp.type == .trend ? trendRadius : dotRadius
                    UIBezierPath(ovalIn: CGRect(origin: point - CGPoint(x: r, y: r), size: CGSize(width: 2 * r, height: 2 * r))).fill()
                }
            } else {
                let curve = UIBezierPath()
                curve.interpolate(points: pd)
                UIColor.black.set()
                curve.lineWidth = lineWidth
                curve.stroke()
                
                UIColor.black.set()
                let fill = UIBezierPath()
                for gp in points {
                    let r = gp.type == .trend ? trendRadius : dotRadius
                    let point = CGPoint(x: xCoor(gp.date), y: yCoor(CGFloat(gp.value)))
                    fill.append(UIBezierPath(ovalIn: CGRect(origin: point - CGPoint(x: r, y: r), size: CGSize(width: 2 * r, height: 2 * r))))
                }
                fill.lineWidth = 0
                fill.fill()
            }
        }
        let text: NSMutableAttributedString? = nil
                    
        if let text = text?.text(alignment: .center) {
            let tsize = text.size()
            let options = [CGRect(x: (size.width - tsize.width) / 2, y: 2, width: tsize.width, height: tsize.height),
                           CGRect(x: (size.width - tsize.width) / 2, y: 2, width: tsize.width, height: tsize.height),
                           CGRect(x: size.width - tsize.width - 4, y: 2, width: tsize.width, height: tsize.height),
                           CGRect(x: (size.width - tsize.width) / 2, y: size.height - tsize.height - 2, width: tsize.width, height: tsize.height),
                           CGRect(x: size.width - tsize.width - 20, y: size.height - tsize.height - 2, width: tsize.width, height: tsize.height),
                           CGRect(origin: CGPoint(x: 4, y: 2), size: tsize),
                           CGRect(x: 4, y: size.height - tsize.height - 2, width: tsize.width, height: tsize.height)
            ]
            
            let trect = options.first {
                let toCheck = $0.insetBy(dx: -5, dy: -5)
                for point in pd {
                    if toCheck.contains(point) {
                        return false
                    }
                }
                return true
            }
            text.draw(in: trect ?? options[0])
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}


extension DateComponents {
    public var getDate: Date {
        return Calendar.current.date(from: self) ?? Date(timeIntervalSince1970: 0)
    }
}
