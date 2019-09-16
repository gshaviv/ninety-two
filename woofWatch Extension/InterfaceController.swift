//
//  InterfaceController.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import WatchKit
import Foundation
import Combine

class InterfaceController: WKInterfaceController {
    @IBOutlet var glucoseLabel: WKInterfaceLabel!
    @IBOutlet var trendLabel: WKInterfaceLabel!
    @IBOutlet var agoLabel: WKInterfaceLabel!
    @IBOutlet var imageView: WKInterfaceImage!
    @IBOutlet var loadingImage: WKInterfaceImage!
    private var observe: AnyCancellable?
    
    private lazy var indicator: EMTLoadingIndicator = EMTLoadingIndicator(interfaceController: self, interfaceImage: loadingImage, width: 16, height: 16, style: .dot)
    enum DimState: Int8 {
        case none
        case little
        case dim
    }
    var isDimmed = DimState.none {
        didSet {
            switch isDimmed {
            case .none:
                animate(withDuration: 0.3) {
                    self.glucoseLabel.setAlpha(1)
                    self.trendLabel.setAlpha(1)
                    self.imageView.setAlpha(1)
                }
                if oldValue != .little {
                    updateTime()
                }
                indicator.hide()
 
            case .little:
                animate(withDuration: 0.3) {
                    self.glucoseLabel.setAlpha(0.65)
                    self.trendLabel.setAlpha(0.0)
                    self.imageView.setAlpha(1)
                }
                updateTime()
                indicator.showWait()

            case .dim:
                animate(withDuration: 0.3) {
                    self.glucoseLabel.setAlpha(0.4)
                    self.trendLabel.setAlpha(0.0)
                    self.imageView.setAlpha(1)
                }
                indicator.showWait()
            }
        }
    }
    var cancelUpdate = false
    var triggered = false
    var lastPoint: GlucosePoint = GlucosePoint(date: Date.distantPast, value: 0)

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        imageView.setAlpha(0)
        loadingImage.setAlpha(0)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: WKExtension.didEnterBackgroundNotification, object: nil)
        observe = WKExtension.extensionDelegate.state.sink(receiveValue: {
            let (state, data) = $0
            switch state {
            case .ready:
                self.isDimmed = .none
                if let last = data.readings.last, last.date != self.lastPoint.date {
                    self.lastPoint = last
                    self.update(data: data)
                    _ = Just(data).receive(on: DispatchQueue.global()).compactMap { self.createImage(data: $0) }.receive(on: DispatchQueue.main).sink { self.imageView.setImage($0) }
                }
                
            case .sending:
                self.isDimmed = .little
                
            case .error:
                self.isDimmed = .none
                self.showError()
            }
        })
    }

    @objc private func didEnterForeground() {
        updateTime()
    }

    override func willActivate() {
        super.willActivate()
        updateTime()
    }

    func updateTime(startTimer: Bool = true) {
        defer {
            if !cancelUpdate && !triggered && startTimer {
                triggered = true
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(1)) {
                    self.triggered = false
                    self.updateTime()
                }
            }
        }
        if startTimer && (cancelUpdate || triggered || WKExtension.shared().applicationState == .background) {
            cancelUpdate = false
            return
        }
        if lastPoint.value > 0 {
            if Date() - lastPoint.date > 1.m && WKExtension.shared().applicationState == .active {
                WKExtension.extensionDelegate.refresh(blank: .none)
            }
            let minutes = Int(Date().timeIntervalSince(lastPoint.date))
            let f = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .medium)
            let attr: NSAttributedString
            if lastPoint.value < 70 {
                attr = (minutes < 90 ? String(format: "%02ld", minutes) : String(format: "%ld:%02ld", minutes / 60, minutes % 60)).styled.color(.white).font(f)
            } else {
                attr = String(format: "%ld:%02ld", minutes / 60, minutes % 60).styled.color(.white).font(f)
            }
            self.agoLabel.setAttributedText(attr)
        } else {
            self.agoLabel.setText("--")
        }

    }

    func update(data: State) {
        guard let last = data.readings.last else {
            return
        }
        isDimmed = .none
        let levelStr = last.value > 70 ? String(format: "%.0lf", last.value) : String(format: "%.1lf", last.value)

        glucoseLabel.setText("\(levelStr)\(data.trendSymbol)")
        if last.value < 70 {
            let tvalue = String(format: "%.1lf",data.trendValue).trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            trendLabel.setText(String(format: "%@%@", data.trendValue > 0 ? "+" : "", tvalue))
        } else {
            trendLabel.setText(String(format: "%@%.1lf", data.trendValue > 0 ? "+" : "", data.trendValue))
        }
        updateTime(startTimer: false)
    }

    func showError() {
        isDimmed = .none
        cancelUpdate = true
        glucoseLabel.setText("?")
        trendLabel.setText("")
        agoLabel.setText("")
    }



    func createImage(data: State) -> UIImage? {
        let colors = [0 ... defaults[.level0]: defaults[.color0] ,
                      defaults[.level0] ... defaults[.level1]: defaults[.color1] ,
                      defaults[.level1] ... defaults[.level2]: defaults[.color2] ,
                      defaults[.level2] ... defaults[.level3]: defaults[.color3] ,
                      defaults[.level3] ... defaults[.level4]: defaults[.color4] ,
                      defaults[.level4] ... 999: defaults[.color5] ]
        let yReference = [35, 40, 50, 60, 70, 80, 100, 120, 140, 160, 180, 200, 225, 250, 275, 300, 350, 400, 500]
        let lineWidth:CGFloat = 3
        let dotRadius:CGFloat = 4

        let width = WKInterfaceDevice.current().screenBounds.size.width * WKInterfaceDevice.current().screenScale
        let points = data.readings
        let (gmin, gmax) = points.reduce((999.0, 0.0)) { (min($0.0, $1.value), max($0.1, $1.value)) }
        var yRange = (min: CGFloat(floor(gmin / 5) * 5), max: CGFloat(ceil(gmax / 10) * 10))
        if yRange.max - yRange.min < 40 {
            let mid = floor((yRange.max + yRange.min) / 2)
            yRange = mid > 89 ? (min: max(mid - 20, 70), max: max(mid - 20, 70) + 40) : (min: yRange.min, max: yRange.min + 40)
        }
        let latest = points.reduce(Date.distantPast) { max($0, $1.date) }
        let maxDate = Date() - latest < 5.m ? latest : Date()
        let xRange = (min: maxDate - 2.h - 45.m, max: maxDate)

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
        let iob = data.iob
        if iob > 0 {
            let scale = WKInterfaceDevice.current().screenScale
            let text = String(format: "BOB %.1lf\n%.2lf", iob, data.insulinAction)
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .center
            let attrib = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 16 * scale, weight: .bold),
                          NSAttributedString.Key.foregroundColor: UIColor(white: 0.1, alpha: 0.7),
                          NSAttributedString.Key.paragraphStyle: pStyle]
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
