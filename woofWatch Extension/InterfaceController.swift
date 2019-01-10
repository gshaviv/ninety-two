//
//  InterfaceController.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import WatchKit
import Foundation

class InterfaceController: WKInterfaceController {
    @IBOutlet var glucoseLabel: WKInterfaceLabel!
    @IBOutlet var trendLabel: WKInterfaceLabel!
    @IBOutlet var agoLabel: WKInterfaceLabel!
    @IBOutlet var imageView: WKInterfaceImage!

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

    func updateTime() {
        if let last = WKExtension.extensionDelegate.readings.last {
            let minutes = Int(Date().timeIntervalSince(last.date) / 60)
            switch minutes {
            case 0:
                agoLabel.setText("Now")

            default:
                agoLabel.setText("\(minutes)m")
            }
        }
    }

    func update() {
        guard let last = WKExtension.extensionDelegate.readings.last else {
            return
        }
        glucoseLabel.setAlpha(1)
        trendLabel.setAlpha(1)
        agoLabel.setAlpha(1)
        imageView.setAlpha(1)

        glucoseLabel.setText("\(Int(round(last.value)))\(WKExtension.extensionDelegate.trendSymbol)")
        trendLabel.setText(String(format: "%@%.1lf", WKExtension.extensionDelegate.trendValue > 0 ? "+" : "", WKExtension.extensionDelegate.trendValue))
        updateTime()
        DispatchQueue.global().async {
            if let image = self.createImage() {
                DispatchQueue.main.async {
                    self.imageView.setImage(image)
                }
            } else {
                DispatchQueue.main.async {
                    self.imageView.setImage(nil)
                }
            }
        }
    }

    func showError() {
        glucoseLabel.setAlpha(1)
        trendLabel.setAlpha(1)
        agoLabel.setAlpha(1)
        imageView.setAlpha(1)
        glucoseLabel.setText("?")
        trendLabel.setText("")
        agoLabel.setText("")
    }

    func blank() {
        glucoseLabel.setAlpha(0.3)
        trendLabel.setAlpha(0.3)
        agoLabel.setAlpha(0.3)
        imageView.setAlpha(0.5)
    }

    func createImage() -> UIImage? {
        let colors = [0 ... 55: UIColor.red,
                      55 ... 70: UIColor.red.lighter(),
                      70 ... 110: UIColor.green,
                      110 ... 140: UIColor.green.lighter(by: 40),
                      140 ... 180: UIColor.green.lighter(by: 70),
                      180 ... 999: UIColor.yellow]
        let yReference = [35, 40, 50, 60, 70, 100, 120, 140, 160, 180, 200, 225, 250, 275, 300, 350, 400, 500]
        let lineWidth:CGFloat = 3
        let dotRadius:CGFloat = 4

        let width = WKInterfaceDevice.current().screenBounds.size.width * WKInterfaceDevice.current().screenScale
        let points = WKExtension.extensionDelegate.readings
        let (gmin, gmax) = points.reduce((999.0, 0.0)) { (min($0.0, $1.value), max($0.1, $1.value)) }
        let yRange = (min: min(max(CGFloat(floor(gmin / 5) * 5), 10), 80), max: max(CGFloat(ceil(gmax / 5) * 5), 140))
        let xRange = (min: points.reduce(Date()) { min($0, $1.date) }, max: Date())

        let size = CGSize(width: width, height: 110 * WKInterfaceDevice.current().screenScale)
        UIGraphicsBeginImageContext(size)

        let ctx = UIGraphicsGetCurrentContext()
        let yScale = size.height / (yRange.max - yRange.min)
        let yCoor = { (yRange.max - $0) * yScale }
        let xScale = size.width / CGFloat(xRange.max - xRange.min)
        let xCoor = { (d: Date) in CGFloat(d - xRange.min) * xScale }
        for (range, color) in colors {
            color.set()
            ctx?.fill(CGRect(x: 0.0, y: yCoor(CGFloat(range.upperBound)), width: size.width, height: CGFloat(range.upperBound - range.lowerBound) * yScale))
        }
        UIColor(white: 0.25, alpha: 0.75).set()
        ctx?.beginPath()
        for y in yReference {
            let yc = yCoor(CGFloat(y))
            ctx?.move(to: CGPoint(x: 0, y: yc))
            ctx?.addLine(to: CGPoint(x: size.width, y: yc))
        }
        var components = xRange.min.components
        components.second = 0
        components.minute = 0
        var xDate = components.date
        let step = 1.h
        repeat {
            ctx?.move(to: CGPoint(x: xCoor(xDate), y: 0))
            ctx?.addLine(to: CGPoint(x: xCoor(xDate), y: size.height))
            xDate += step
        } while xDate < xRange.max
        ctx?.strokePath()
        let p = points.map { CGPoint(x: xCoor($0.date), y: yCoor(CGFloat($0.value))) }
        if !p.isEmpty {
            let curve = UIBezierPath()
                curve.move(to: p[0])
                curve.addCurveThrough(points: p[1...], contractionFactor: 0.65)
            UIColor.darkGray.set()
            curve.lineWidth = lineWidth
            curve.stroke()

            UIColor.black.set()
            let fill = UIBezierPath()
            let dotSize = CGSize(width: 2 * dotRadius, height: 2 * dotRadius)
            for point in p {
                fill.append(UIBezierPath(ovalIn: CGRect(origin: point - CGPoint(x: dotRadius, y: dotRadius), size: dotSize)))
            }
            fill.lineWidth = 0
            fill.fill()
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}
