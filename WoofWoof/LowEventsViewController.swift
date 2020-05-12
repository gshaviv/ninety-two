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
import Sqlable

class LowEventsViewController: UIViewController {
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        edgesForExtendedLayout = []
        title = "Low Events"
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
        let readings = (try? Storage.default.db.perform(GlucosePoint.read().filter(GlucosePoint.date > start && GlucosePoint.date < end && GlucosePoint.value > 0).orderBy(GlucosePoint.date))) ?? []
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
                lowEvents.append(currentEvent)
                inEvent = false
                currentEvent = []
            }
            lastPoint = point
        }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let render = UIGraphicsImageRenderer(size: CGSize(width: view.width, height: view.height), format: format).image { (_) in
            guard lowEvents.count > 0 else {
                return
            }
            let normalFont = UIFont.systemFont(ofSize: 11)
            let rect = CGRect(x: 0, y: 0, width: self.view.width, height: self.view.height)
            let ctx = UIGraphicsGetCurrentContext()
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
            UIColor.secondaryLabel.setStroke()
            ctx?.beginPath()
            for y in stride(from: yMaxValue, to: yMinValue, by: -10) {
                let yc = yPos(y)
                ctx?.move(to: CGPoint(x: 0, y: yc))
                ctx?.addLine(to: CGPoint(x: graphRect.maxX, y: yc))
            }
            ctx?.strokePath()
            ctx?.setLineWidth(0.5)
            for x in 0 ... 12 {
                let time = String(format: "%02ld",(x == 12 ? 0 : x) * 2).styled.font(normalFont).color(UIColor.label)
                let size = time.size()
                let xCenter = CGFloat(x) * graphRect.width / 12.0
                let area = CGRect(origin: CGPoint(x: min(xCenter - size.width / 2,graphRect.maxX - size.width), y: graphRect.maxY - size.height), size: size)
                if x > 0 && x < 12 {
                    time.draw(in: area)
                }
                UIColor.secondaryLabel.setStroke()
                ctx?.beginPath()
                ctx?.move(to: CGPoint(x: xCenter, y: 0))
                ctx?.addLine(to: CGPoint(x: xCenter, y: area.minY))
                ctx?.strokePath()
            }
            let xPos = { (time:TimeInterval) -> CGFloat in CGFloat(time) / 86400 * graphRect.width }
            ctx?.saveGState()
            ctx?.clip(to: graphRect)
            
            UIColor.red.setStroke()
            let fill = UIColor {
                switch $0.userInterfaceStyle {
                case .unspecified:
                    return UIColor(red: 1, green: 0, blue: 0, alpha: 0.1)
                case .light:
                    return UIColor(red: 1, green: 0, blue: 0, alpha: 0.1)
                case .dark:
                    return UIColor(red: 0.5, green: 0, blue: 0, alpha: 0.5)
                @unknown default:
                    return UIColor(red: 1, green: 0, blue: 0, alpha: 0.1)
                }
            }
            fill.setFill()
            
            for event in lowEvents {
                guard let eventStart = event.first else {
                    continue
                }
                let base = eventStart.date.startOfDay
                let points = event.map { CGPoint(x: xPos($0.date - base), y: yPos($0.value)) }
                let path = UIBezierPath()
                path.append(Plot(points: points).line(from: points.first!.x, to: points.last!.x, moveToFirst: true))
                path.addLine(to: points[0])
                path.fill()
                path.stroke()
                if points.map({ $0.x }).biggest() > graphRect.width {
                    let later = base + 24.h
                    let points = event.map { CGPoint(x: xPos($0.date - later), y: yPos($0.value)) }
                    let path = UIBezierPath()
                    path.append(Plot(points: points).line(from: points.first!.x, to: points.last!.x, moveToFirst: true))
                    path.addLine(to: points[0])
                    path.fill()
                    path.stroke()
                }
            }
            ctx?.restoreGState()
//            UIColor.label.setStroke()
//            ctx?.setLineWidth(1)
//            ctx?.stroke(graphRect)
        }
        return render
    }
}
