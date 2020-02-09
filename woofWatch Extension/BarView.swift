//
//  BarView.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2020.
//  Copyright © 2020 TivStudio. All rights reserved.
//

import SwiftUI

struct BarView: View {
    let bars: [(values: [CGFloat], marks: Summary.Marks)]
    private var colors: [UIColor] = [#colorLiteral(red: 0.1621245146, green: 0.2436933815, blue: 1, alpha: 0.8),#colorLiteral(red: 0.5664476752, green: 0.1350907288, blue: 0.2568396887, alpha: 0.8)]
    enum ChartType {
        case stacked
        case clustered
    }
    private var chartType = ChartType.stacked
    private var showText = true
    
    func clustered() -> BarView {
        var copy = BarView(bars)
        copy.colors = colors
        copy.chartType = .clustered
        copy.showText = showText
        return copy
    }
    
    func colors(_ colors: [UIColor]) -> BarView {
        var copy = BarView(bars)
        copy.colors = colors
        copy.chartType = self.chartType
        copy.showText = showText
        return copy
    }
    
    func hideLabels() -> BarView {
        var copy = BarView(bars)
        copy.colors = colors
        copy.chartType = chartType
        copy.showText = false
        return copy
    }
    
    init(_ v: [(values: [CGFloat], marks: Summary.Marks)]) {
        #if DEBUG
        v.forEach {
            assert($0.values.count == v[0].values.count, "bars do not all have the same number of values")
        }
        #endif
        bars = v
    }
    
    init(_ v: [(values: [Double], marks: Summary.Marks)]) {
        #if DEBUG
        v.forEach {
            assert($0.values.count == v[0].values.count, "bars do not all have the same number of values")
        }
        #endif
        bars = v.map { (values: $0.values.map { CGFloat($0) }, marks: $0.marks) }
    }
    
    init(_ v: [(values: [Int], marks: Summary.Marks)]) {
        #if DEBUG
        v.forEach {
            assert($0.values.count == v[0].values.count, "bars do not all have the same number of values")
        }
        #endif
        bars = v.map { (values: $0.values.map { CGFloat($0) }, marks: $0.marks) }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: true) {
                Image(uiImage: self.makeImage(h: geometry.size.height))
                }
        }
    }
    
    func makeImage(h: CGFloat) -> UIImage {
        if bars.isEmpty {
            return UIImage(systemName: "chart.bar.fill")!
        }
        
        let barWidth: CGFloat = 20
        let spacing: CGFloat = chartType == .stacked ? 4 : 6
        let xOffset: CGFloat = 0
        let interSpacing: CGFloat = 0
        let width: CGFloat
        let clusterWidth: CGFloat
        switch self.chartType {
        case .stacked:
            width = CGFloat(bars.count) * (barWidth + spacing) - spacing + xOffset
            clusterWidth = barWidth
            
        case .clustered:
            let clusterCount = CGFloat(bars[0].values.count)
            clusterWidth = (barWidth + interSpacing) * clusterCount - interSpacing
            width = CGFloat(bars.count) * (clusterWidth + spacing) - spacing + xOffset
        }
        let gh = h
        let values = { () -> [CGFloat] in
            switch self.chartType {
            case .stacked:
                var v = self.bars.map { $0.values.reduce(0,+) }
                for bd in bars {
                    if bd.values.countMatches(where: { $0 > 0 }) > 1 {
                        v.append(0)
                        return v
                    }
                }
                return v
            case .clustered:
                return self.bars.flatMap { $0.values }
            }
        }()
            
        
        let maxValue = values.max()!
        let minValue = values.min()!
        var v0 = minValue
        var v1 = maxValue
        var step: CGFloat = 10
        for x:CGFloat in [0.5, 1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000] {
            v0 = max(floor(minValue / x) * x - x, 0)
            v1 = ceil(maxValue / x) * x
            if (v1 - v0) / x < 6 {
                step = x
                break
            }
        }
        
        #if os(iOS)
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: h), true, UIScreen.main.scale)
        #else
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: h), true, WKInterfaceDevice.current().screenScale)
        #endif
        let ctx = UIGraphicsGetCurrentContext()
        
        UIColor(white: 0.7, alpha: 1).set()
        var x0 = xOffset
        ctx?.saveGState()
        if v1 - v0 > 2 * step {
            let clip = UIBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: h))
            clip.usesEvenOddFillRule = true
            bars.forEach {
                defer {
                    x0 += clusterWidth + spacing
                }
                if $0.marks.contains(.seperator) {
                    for y in stride(from: v0 + step, to: v1, by: step) {
                        let text = "\(Double(y).decimal(digits: 0))".styled.systemFont(size: 12).color(UIColor(white: 0.5, alpha: 1))
                        let size = text.size()
                        let rect = CGRect(origin: CGPoint(x: x0 + 1, y: (1 - (y - v0) / (v1 - v0)) * gh - size.height / 2), size: size)
                        text.draw(in: rect)
                        clip.append(UIBezierPath(rect: rect))
                    }
                }
            }
            clip.addClip()
        }
        
        for y in stride(from: v0, to: v1 + 0.5, by: step) {
            ctx?.move(to: CGPoint(x: xOffset, y: (1 - (y - v0) / (v1 - v0)) * gh))
            ctx?.addLine(to: CGPoint(x: width, y: (1 - (y - v0) / (v1 - v0)) * gh))
        }
        ctx?.strokePath()
        ctx?.restoreGState()
        
        x0 = xOffset
        bars.forEach { bd in
            let mark = bd.marks
            var y = gh
            let total = self.chartType == .stacked ? bd.values.reduce(0,+) : 0
            bd.values.enumerated().forEach {
                if $0.offset == 0 && mark.contains(.seperator) {
                    ctx?.move(to: CGPoint(x: x0 - spacing / 2, y: 0))
                    ctx?.addLine(to: CGPoint(x: x0 - spacing / 2, y: gh))
                    UIColor(white: 0.35, alpha: 1).setStroke()
                    ctx?.strokePath()
                } else if $0.offset == 0 && self.chartType == .clustered {
                    ctx?.move(to: CGPoint(x: x0 - spacing / 2, y: gh - 10))
                    ctx?.addLine(to: CGPoint(x: x0 - spacing / 2, y: gh))
                    ctx?.move(to: CGPoint(x: x0 - spacing / 2, y: 10))
                    ctx?.addLine(to: CGPoint(x: x0 - spacing / 2, y: 0))
                    UIColor(white: 0.35, alpha: 1).setStroke()
                    ctx?.strokePath()
                }
                
                let barRect: CGRect
                switch self.chartType {
                case .clustered:
                    let barH = ($0.element - v0) / (v1 - v0) * gh
                    barRect = CGRect(x: x0, y: y - barH, width: barWidth, height: barH)
                    x0 += barWidth
                    if $0.offset < bd.values.count - 1 {
                        x0 += interSpacing
                    }
                    
                case .stacked:
                    let barH = ($0.element - v0) / (v1 - v0) * gh * $0.element / total
                    barRect = CGRect(x: x0, y: y - barH, width: barWidth, height: barH)
                    y -= barH
                }
                
                if barRect.height > 0 {
                    self.colors[$0.offset].setFill()
                    ctx?.fill(barRect)
                }
                if $0.offset == bd.values.count - 1 && mark.contains(.mark) {
                    UIColor.lightGray.setFill()
                    switch self.chartType {
                    case .clustered:
                        let cx = x0 - ((CGFloat(bd.values.count) * (barWidth + interSpacing)) - interSpacing) / 2
                        let mv = bd.values.max() ?? 0
                        let cy = gh - (mv - v0) / (v1 - v0) * gh
                        let markRect = CGRect(center: CGPoint(x: cx, y: max(cy - 14, 8)), size: CGSize(width: ((CGFloat(bd.values.count) * (barWidth + interSpacing)) - interSpacing), height: 2))
                        UIBezierPath(rect: markRect).fill()

                    case .stacked:
                        let markRect = CGRect(center: CGPoint(x: barRect.midX, y: max(barRect.minY - 8, 8)), size: CGSize(width: 8, height: 8))
                        UIBezierPath(ovalIn: markRect).fill()
                    }
                }
            }
            switch self.chartType {
            case .stacked:
                x0 += barWidth + spacing
            case .clustered:
                x0 += spacing
            }
        }
        
        x0 = xOffset
        var lastRects = [CGRect]()
        if showText {
            bars.forEach { datum in
                var y0 = gh
                var barRects = [CGRect]()
                let total = self.chartType == .stacked ? datum.values.reduce(0,+) : 0
                datum.values.enumerated().forEach {
                    let barRect: CGRect
                    switch self.chartType {
                    case .clustered:
                        let barH = ($0.element - v0) / (v1 - v0) * gh
                        barRect = CGRect(x: x0, y: y0 - barH, width: barWidth, height: barH)
                        x0 += barWidth
                        if $0.offset < datum.values.count - 1 {
                            x0 += interSpacing
                        }
                        
                    case .stacked:
                        let barH = ($0.element - v0) / (v1 - v0) * gh * $0.element / total
                        barRect = CGRect(x: x0, y: y0 - barH, width: barWidth, height: barH)
                        y0 -= barH
                    }
                    
                    guard $0.element > 0 else {
                        return
                    }
                    
                    
                    let textValue = Double($0.element).maxDigits(1).styled.color(.white).systemFont(size: 12)
                    let size = textValue.size()
                    var textRect = CGRect(x: barRect.midX - size.width / 2,
                                          y: ($0.offset < datum.values.count - 1 || datum.marks.contains(.bottomText)) && self.chartType == .stacked ? barRect.maxY - size.height : barRect.minY + 2,
                                          width: size.width,
                                          height: size.height)
                    if textRect.maxY > h {
                        textRect.origin.y = barRect.minY - size.height
                    }
                    if textRect.maxX > width {
                        textRect.origin.x = width - size.width
                    }
                    if textRect.minX < 0 {
                        textRect.origin.x = 0
                    }
                    outer: for trect in [textRect, CGRect(origin: CGPoint(x: textRect.origin.x, y: textRect.minY - textRect.height), size: textRect.size)] {
                        for rect in lastRects {
                            if rect.intersects(trect) {
                                continue outer
                            }
                        }
                        
                        textValue.draw(in: trect)
                        barRects.append(trect)
                        break
                    }
                }
                
                switch chartType {
                case .stacked:
                    x0 += barWidth + spacing
                    
                case .clustered:
                    x0 += spacing
                }
                lastRects = barRects
            }
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage(systemName: "chart.bar.fill")!
    }
}

#if DEBUG
struct BarView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BarView([(values: [113], marks: .bottomText),
                     (values: [114.23], marks: .bottomText),
                     (values: [113.5], marks: [.bottomText,.seperator]),
                     (values: [113.8], marks: .bottomText),
                     (values: [116], marks: .bottomText),
                     (values: [111], marks: .bottomText),
                     (values: [119.5], marks: .bottomText),
                     (values: [118], marks: .bottomText),
                     (values: [119], marks: .bottomText),
                     (values: [113], marks: .bottomText),
                     (values: [106.5], marks: .bottomText)])
            BarView([(values: [2,8], marks: .none),
                     (values: [0,5], marks: .seperator),
                     (values: [0,0], marks: .none),
                     (values: [1,0], marks: .none),
                     (values: [0.5,6.2], marks: .none),
                     (values: [0.2,0], marks: .none),
                     (values: [0,3], marks: .none),
                     (values: [2,8], marks: .none),
                     (values: [0,5], marks: .seperator),
                     (values: [0,0], marks: .none),
                     (values: [1,0], marks: .none),
                     (values: [0.5,6.2], marks: .none),
                     (values: [0.2,0], marks: .none),
                     (values: [0,3], marks: .mark)])
                .colors([UIColor.red.darker(by: 60),
                         UIColor.yellow.darker(by: 60)])
                .clustered()
        }
        .previewLayout(PreviewLayout.fixed(width: 260, height: 150))
    }
   

}
#endif
