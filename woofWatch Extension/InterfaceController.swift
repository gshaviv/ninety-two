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
    var isDimmed = false {
        didSet {
            glucoseLabel.setAlpha(isDimmed ? 0.3 : 1)
            trendLabel.setAlpha(isDimmed ? 0.3 : 1)
            agoLabel.setAlpha(isDimmed ? 0.3 : 1)
            imageView.setAlpha(isDimmed ? 0.65 : 1)
            if !isDimmed {
                updateTime()
            }
        }
    }
    var cancelUpdate = false
    var triggered = false

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: WKExtension.didEnterBackgroundNotification, object: nil)
    }

    @objc private func didEnterForeground() {
        updateTime()
    }

    override func willActivate() {
        super.willActivate()
        updateTime()
    }

    func updateTime() {
        if isDimmed || triggered {
            return
        }
        if cancelUpdate {
            cancelUpdate = false
            return
        }
        if WKExtension.shared().applicationState == .background || isDimmed {
            return
        }
        if let last = WKExtension.extensionDelegate.readings.last {
            let minutes = Int(Date().timeIntervalSince(last.date))
            let f = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .medium)
            let attr = String(format: "%ld:%02ld", minutes / 60, minutes % 60).styled.color(.white).font(f)
            self.agoLabel.setAttributedText(attr)
        } else {
            self.agoLabel.setText("--")
        }
        triggered = true
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(1)) {
            self.triggered = false
            self.updateTime()
        }
    }

    func update() {
        guard let last = WKExtension.extensionDelegate.readings.last else {
            return
        }
        isDimmed = false

        glucoseLabel.setText("\(Int(round(last.value)))\(WKExtension.extensionDelegate.trendSymbol)")
        trendLabel.setText(String(format: "%@%.1lf", WKExtension.extensionDelegate.trendValue > 0 ? "+" : "", WKExtension.extensionDelegate.trendValue))
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
        isDimmed = false
        cancelUpdate = true
        glucoseLabel.setText("?")
        trendLabel.setText("")
        agoLabel.setText("")
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
        let yRange = (min: CGFloat(floor(gmin / 5) * 5), max: CGFloat(ceil(gmax / 10) * 10))
        let latest = points.reduce(Date.distantPast) { max($0, $1.date) }
        let maxDate = Date() - latest < 5.m ? latest : Date()
        let xRange = (min: maxDate - 3.h, max: maxDate)

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
//                curve.move(to: p[0])
//                curve.addCurveThrough(points: p[1...], contractionFactor: 0.65)
            curve.interpolate(points: p)
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
        let iob = WKExtension.extensionDelegate.iob
        if iob > 0 {
            let scale = WKInterfaceDevice.current().screenScale
            let text = "BOB \(String(format: "%.1lf", iob))"
            let attrib = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 16 * scale, weight: .bold), NSAttributedString.Key.foregroundColor: UIColor(white: 0.1, alpha: 0.7)]
            let styled = NSAttributedString(string: text, attributes: attrib)
            let tsize = styled.size()
            let options = [CGRect(x: (size.width - tsize.width) / 2, y: 2 * scale, width: tsize.width, height: tsize.height),
                           CGRect(origin: CGPoint(x: 4 * scale, y: 2 * scale), size: tsize),
                           CGRect(x: (size.width - tsize.width) / 2, y: 2 * scale, width: tsize.width, height: tsize.height),
                           CGRect(x: size.width - tsize.width - 4 * scale, y: 2 * scale, width: tsize.width, height: tsize.height),
                           CGRect(x: (size.width - tsize.width) / 2, y: size.height - tsize.height - 2 * scale, width: tsize.width, height: tsize.height),
                           CGRect(x: size.width - tsize.width - 4 * scale, y: size.height - tsize.height - 2 * scale, width: tsize.width, height: tsize.height),
                           CGRect(x: 4 * scale, y: size.height - tsize.height - 2 * scale, width: tsize.width, height: tsize.height)]

            let trect = options.first {
                let toCheck = $0.insetBy(dx: -5 * scale, dy: -5 * scale)
                for point in p {
                    if toCheck.contains(point) {
                        return false
                    }
                }
                return true
            }
            styled.draw(in: trect ?? options[0])
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}
