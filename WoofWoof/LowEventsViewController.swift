//
//  LowEventsViewController.swift
//  WoofWoof
//
//  Created by Guy on 11/05/2020.
//  Copyright © 2020 TivStudio. All rights reserved.
//

import Foundation
import UIKit
import WoofKit
import GRDB

class LowEventsViewController: UIViewController {
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        edgesForExtendedLayout = []
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = UIImageView()
        imageView.contentMode = .scaleToFill
    }
    
    var imageView: UIImageView {
        view as! UIImageView
    }
    
    var lastSize = CGSize.zero
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard imageView.image == nil || lastSize != view.frame.size else {
            return
        }
        defer {
            lastSize = view.frame.size
        }
        imageView.image = makeImage()
    }
    
    func makeImage() -> UIImage? {
        let end = Date()
        let start = end - defaults.summaryPeriod.d
        let readings = Storage.default.db.evaluate(
            GlucosePoint.filter(GlucosePoint.Column.date > start && GlucosePoint.Column.date < end && GlucosePoint.Column.value > 0).order(GlucosePoint.Column.date)
        ) ?? []
        let minValue = readings.map { $0.value }.min() ?? 60
        
        var lowEvents = [[GlucosePoint]]()
        var lastPoint:GlucosePoint? = nil
        var currentEvent = [GlucosePoint]()
        var inEvent = false
        for point in readings {
            if point.value < 70 {
                if !inEvent, let last = lastPoint {
                    currentEvent.append(last)
                }
                inEvent = true
                currentEvent.append(point)
            } else if inEvent {
                currentEvent.append(point)
                if currentEvent.map({ $0.value }).min() ?? 0 < 67 {
                    lowEvents.append(currentEvent)
                }
                inEvent = false
                currentEvent = []
            }
            lastPoint = point
        }
        title = "\(lowEvents.count) Low Events"
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let render = UIGraphicsImageRenderer(size: CGSize(width: view.width, height: view.height), format: format).image { (_) in
            guard lowEvents.count > 0 else {
                return
            }
            let isSmall = UIScreen.main.bounds.width < UIScreen.main.bounds.height
            let normalFont = UIFont.systemFont(ofSize: isSmall ? 11 : 13)
            let rect = CGRect(x: 0, y: 0, width: self.view.width, height: self.view.height)
            let ctx = UIGraphicsGetCurrentContext()
            UIColor.systemBackground.set()
            ctx?.fill(rect)
            let yMaxValue = Double(70)
            let yMinValue = floor(minValue / 5) * 5
            let topMargin:Double = 0
            let yDist = Double(rect.height) - topMargin
            let yPos = { (y: Double) in CGFloat((yMaxValue - y) / (yMaxValue - yMinValue) * yDist) }
            ctx?.translateBy(x: 0, y: CGFloat(topMargin))
            var wMax:CGFloat = 0
            for y in stride(from: yMaxValue, to: yMinValue, by: -10) {
                let num = "\(Int(y))".styled.font(normalFont).color(UIColor.label)
                let s = num.size()
                wMax = max(wMax, s.width)
                let yCoor = yPos(y)
                let area = CGRect(x: 0, y: max(yCoor - s.height / 2,0), width: s.width, height: s.height)
                num.draw(in: area)
            }
            ctx?.translateBy(x: wMax + 1, y: 0)
            let graphRect = rect.inset(by: UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0, right: wMax + 1))
            
            ctx?.setLineWidth(0.5)
            for y in stride(from: yMaxValue, to: yMinValue, by: isSmall ? -10 : -5) {
                let yc = yPos(y)
                UIColor.secondaryLabel.setStroke()
                if Int(y) % 10 == 5 {
                    UIColor.tertiaryLabel.setStroke()
                }
                ctx?.beginPath()
                ctx?.move(to: CGPoint(x: 0, y: yc))
                ctx?.addLine(to: CGPoint(x: graphRect.maxX, y: yc))
                ctx?.strokePath()
            }
            ctx?.setLineWidth(0.5)
            for x in 0 ... 24 {
                let time = String(format: "%02ld",x == 24 ? 0 : x).styled.font(normalFont).color(UIColor.label)
                let size = time.size()
                let xCenter = CGFloat(x) * graphRect.width / 24.0
                let area = CGRect(origin: CGPoint(x: min(xCenter - size.width / 2,graphRect.maxX - size.width), y: graphRect.maxY - size.height), size: size)
                if  x % 2 == 0 {
                    time.draw(in: area)
                }
                if !isSmall || x % 2 == 0 {
                    if x % 2 == 0 {
                        UIColor.secondaryLabel.setStroke()
                    } else {
                        UIColor.tertiaryLabel.setStroke()
                    }
                    ctx?.beginPath()
                    ctx?.move(to: CGPoint(x: xCenter, y: 0))
                    ctx?.addLine(to: CGPoint(x: xCenter, y: x % 2 == 1 ? graphRect.maxY : area.minY))
                    ctx?.strokePath()
                    UIColor.secondaryLabel.setStroke()
                }
            }
            let xPos = { (time:TimeInterval) -> CGFloat in CGFloat(time) / 86400 * graphRect.width }
            ctx?.saveGState()
            ctx?.clip(to: graphRect)
            
            UIColor {
                switch $0.userInterfaceStyle {
                case .unspecified, .light:
                    return UIColor.red
                case .dark:
                    return UIColor(red: 1, green: 0.5, blue: 0.5, alpha: 1)
                @unknown default:
                    return UIColor.red
                }
            }.setStroke()
            UIColor {
                switch $0.userInterfaceStyle {
                case .unspecified:
                    return UIColor(red: 1, green: 0, blue: 0, alpha: 0.1)
                case .light:
                    return UIColor(red: 1, green: 0, blue: 0, alpha: 0.4)
                case .dark:
                    return UIColor(red: 0.5, green: 0, blue: 0, alpha: 0.65)
                @unknown default:
                    return UIColor(red: 1, green: 0, blue: 0, alpha: 0.1)
                }
            }.setFill()
            for event in lowEvents {
                guard let eventStart = event.first else {
                    continue
                }
                let base = eventStart.date.startOfDay
                let points = event.map { CGPoint(x: xPos($0.date - base), y: yPos($0.value)) }
                let path = UIBezierPath()
                path.append(Plot(points: points).line(from: points.first!.x, to: points.last!.x, moveToFirst: true))
                path.addLine(to: points[0])
                path.lineWidth = 1/UIScreen.main.scale
                path.fill()
                path.stroke()
                if points.map({ $0.x }).biggest() > graphRect.width {
                    let later = base + 24.h
                    let points = event.map { CGPoint(x: xPos($0.date - later), y: yPos($0.value)) }
                    let path = UIBezierPath()
                    path.append(Plot(points: points).line(from: points.first!.x, to: points.last!.x, moveToFirst: true))
                    path.addLine(to: points[0])
                    path.lineWidth = 1/UIScreen.main.scale
                    path.fill()
                    path.stroke()
                }
            }
            ctx?.restoreGState()
            for x in 0 ... 12 {
                let time = String(format: "%02ld",(x == 12 ? 0 : x) * 2).styled.font(normalFont).color(UIColor.label)
                let size = time.size()
                let xCenter = CGFloat(x) * graphRect.width / 12.0
                let area = CGRect(origin: CGPoint(x: min(xCenter - size.width / 2,graphRect.maxX - size.width), y: graphRect.maxY - size.height), size: size)
                if x > 0 && x < 12 {
                    time.draw(in: area)
                }
            }
//            UIColor.label.setStroke()
//            ctx?.setLineWidth(1)
//            ctx?.stroke(graphRect)
        }
        return render
    }
}
