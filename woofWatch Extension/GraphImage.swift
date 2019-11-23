//
//  GraphImage.swift
//  woofWatch Extension
//
//  Created by Guy on 19/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

struct GraphImage: View {
    @State private var image: UIImage = UIImage(systemName: "waveform.path.ecg")!
    @ObservedObject private var state: AppState
    private var size: CGSize
    @State private var lastTime = Date.distantPast
    
    var body: some View {
        #if targetEnvironment(simulator)
        return Image(uiImage: GraphImage.createImage(state: state, size: size) ?? image)
        #else
        if let last = state.data.readings.last?.date, last != lastTime, let newImage = GraphImage.createImage(state: state, size: size) {
            DispatchQueue.main.async {
                self.lastTime = last
                self.image = newImage
            }
        }
        return Image(uiImage: image )
        #endif
    }
    
    init(state: AppState, size: CGSize) {
        self.state = state
        self.size = size
    }
    
    static func createImage(state: AppState, size: CGSize) -> UIImage? {
        let data = state.data
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
        
        let points = data.readings
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
        #if targetEnvironment(simulator)
        let xRange = (min: maxDate - 1.h, max: maxDate)
        #else
        let xRange = (min: maxDate - 2.h - 45.m, max: maxDate)
        #endif
        
        UIGraphicsBeginImageContextWithOptions(size, true, WKInterfaceDevice.current().screenScale)
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
        var union = CGRect(origin: .zero, size: size)
        var lastY:CGFloat = 0

        for y in yReference.reversed() {
            let yc = yCoor(CGFloat(y))
            let attrib = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 13, weight: .light),
                          NSAttributedString.Key.foregroundColor: defaults[.useDarkGraph] ? UIColor(white: 0.6, alpha: 1) : UIColor(white: 0.25, alpha: 1)]
            let styled = NSAttributedString(string: "\(y)", attributes: attrib)
            let tsize = styled.size()
            if !defaults[.useDarkGraph] {
                UIColor(white: 0.25, alpha: 0.5).set()
            } else {
                UIColor(white: 0.5, alpha: 1).set()
            }
            ctx?.move(to: CGPoint(x: tsize.width + 8, y: yc))
            ctx?.addLine(to: CGPoint(x: size.width, y: yc))
            ctx?.strokePath()
            let trect = CGRect(origin: CGPoint(x: 4, y: yc - tsize.height / 2), size: tsize)
            if trect.minY > lastY {
                if !defaults[.useDarkGraph] {
                    UIColor(white: 0.25, alpha: 0.75).set()
                } else {
                    UIColor(white: 0.7, alpha: 1).set()
                }
                styled.draw(in: trect)
                clip.append(UIBezierPath(rect: trect.inset(by: UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 0))))
                union = union.union(trect)
                lastY = trect.maxY
            }
        }
        clip.append(UIBezierPath(rect: union))
        clip.usesEvenOddFillRule = true
        ctx?.saveGState()
        clip.addClip()
        var components = xRange.min.components
        components.second = 0
        components.minute = 0
        var xDate = components.getDate
        let step = 1.h
        repeat {
            ctx?.move(to: CGPoint(x: xCoor(xDate), y: 0))
            ctx?.addLine(to: CGPoint(x: xCoor(xDate), y: size.height))
            xDate += step
        } while xDate < xRange.max
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
        let text: String?
        if state.state == .snapshot {
            text = nil
        } else if state.data.iob > 0 {
            let ageInHours = Int(data.sensorAge / 1.h)
            text = ageInHours < 24 ? "\(ageInHours)h\n\(state.data.batteryLevel)%" : ageInHours % 24 == 0 ? "\(ageInHours / 24)d\n\(state.data.batteryLevel)%" : "\(ageInHours / 24)d:\(ageInHours % 24)h\n\(state.data.batteryLevel)%"
        } else if state.data.sensorAge > 10.d {
            let ageInHours = Int(data.sensorAge / 1.h)
            text = ageInHours < 24 ? "\(ageInHours)h" : ageInHours % 24 == 0 ? "\(ageInHours / 24)d" : "\(ageInHours / 24)d:\(ageInHours % 24)h"
        } else {
            text = nil
        }
        if let text = text {
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .center
            let attrib = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 16, weight: .bold),
                          NSAttributedString.Key.foregroundColor: defaults[.useDarkGraph] ? UIColor(white: 0.9, alpha: 0.75) : UIColor(white: 0.1, alpha: 0.7),
                          NSAttributedString.Key.paragraphStyle: pStyle]
            let styled = NSAttributedString(string: text, attributes: attrib)
            let tsize = styled.size()
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
            if let trect = trect {
                styled.draw(in: trect)
            }
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}
