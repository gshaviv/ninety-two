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
        let yReference = [35, 40, 50, 60, 70, 80, 100, 120, 140, 160, 180, 200, 225, 250, 275, 300, 350, 400, 500]
        let lineWidth:CGFloat = 1.5
        let dotRadius:CGFloat = 3
        let trendRadius:CGFloat = 1.5
        
        let points = data.readings
        let (gmin, gmax) = points.reduce((999.0, 0.0)) { (min($0.0, $1.value), max($0.1, $1.value)) }
        var yRange = (min: CGFloat(floor(gmin / 5) * 5), max: CGFloat(ceil(gmax / 10) * 10))
        if yRange.max - yRange.min < 40 {
            let mid = floor((yRange.max + yRange.min) / 2)
            yRange = mid > 89 ? (min: max(mid - 20, 70), max: max(mid - 20, 70) + 40) : (min: yRange.min, max: yRange.min + 40)
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
        let xScale = size.width / CGFloat(xRange.max - xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - xRange.min) * xScale }
        for (range, color) in colors {
            color.set()
            ctx?.fill(CGRect(x: 0.0, y: yCoor(CGFloat(range.upperBound)), width: size.width, height: CGFloat(range.upperBound - range.lowerBound) * yScale))
        }
        UIColor(white: 0.25, alpha: 0.5).set()
        ctx?.beginPath()
        for y in yReference {
            let yc = yCoor(CGFloat(y))
            ctx?.move(to: CGPoint(x: 0, y: yc))
            ctx?.addLine(to: CGPoint(x: size.width, y: yc))
        }
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
        let p = points.map { CGPoint(x: xCoor($0.date), y: yCoor(CGFloat($0.value))) }
        if !points.isEmpty {
            let curve = UIBezierPath()
            curve.interpolate(points: p)
            UIColor.black.set()
            curve.lineWidth = lineWidth
            curve.stroke()
            
            UIColor.black.set()
            let fill = UIBezierPath()
            for gp in points {
                let r = gp.isTrend ? trendRadius : dotRadius
                let point = CGPoint(x: xCoor(gp.date), y: yCoor(CGFloat(gp.value)))
                fill.append(UIBezierPath(ovalIn: CGRect(origin: point - CGPoint(x: r, y: r), size: CGSize(width: 2 * r, height: 2 * r))))
            }
            fill.lineWidth = 0
            fill.fill()
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
                          NSAttributedString.Key.foregroundColor: UIColor(white: 0.1, alpha: 0.7),
                          NSAttributedString.Key.paragraphStyle: pStyle]
            let styled = NSAttributedString(string: text, attributes: attrib)
            let tsize = styled.size()
            let options = [CGRect(x: (size.width - tsize.width) / 2, y: 2, width: tsize.width, height: tsize.height),
                           CGRect(origin: CGPoint(x: 4, y: 2), size: tsize),
                           CGRect(x: (size.width - tsize.width) / 2, y: 2, width: tsize.width, height: tsize.height),
                           CGRect(x: size.width - tsize.width - 4, y: 2, width: tsize.width, height: tsize.height),
                           CGRect(x: (size.width - tsize.width) / 2, y: size.height - tsize.height - 2, width: tsize.width, height: tsize.height),
                           CGRect(x: size.width - tsize.width - 4, y: size.height - tsize.height - 2, width: tsize.width, height: tsize.height),
                           CGRect(x: 4, y: size.height - tsize.height - 2, width: tsize.width, height: tsize.height)]
            
            let trect = options.first {
                let toCheck = $0.insetBy(dx: -5, dy: -5)
                for point in p {
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
