//
//  BarView.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2020.
//  Copyright © 2020 TivStudio. All rights reserved.
//

import SwiftUI

struct BarView: View {
    let bars: [CGFloat]
    let marks: [Summary.Marks]
    
    init(_ v: [Double], marks: [Summary.Marks] = []) {
        bars = v.map { CGFloat($0) }
        self.marks = marks
    }
    
    init(_ v: [Int], marks: [Summary.Marks] = []) {
        bars = v.map { CGFloat($0) }
        self.marks = marks
    }
    
    init(_ v: [CGFloat], marks: [Summary.Marks] = []) {
        bars = v
        self.marks = marks
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
        let spacing: CGFloat = 4
        let xOffset: CGFloat = 0
        let width = CGFloat(bars.count) * (barWidth + spacing) - spacing + xOffset
//        let th = "1".styled.color(.white).systemFont(size: 13).size().height
        let gh = h
        
        var v0 = floor(bars.min()! / 10) * 10.0
        if v0 - 10 >= 0 {
            v0 -= 10
        }
        let v1 = ceil(bars.max()! / 10) * 10.0
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: h), true, WKInterfaceDevice.current().screenScale)
        let ctx = UIGraphicsGetCurrentContext()
        
        UIColor(white: 0.25, alpha: 1).set()
        for y in stride(from: v0, to: v1, by: 10.0) {
            ctx?.move(to: CGPoint(x: xOffset, y: (y - v0) / (v1 - v0) * gh))
            ctx?.addLine(to: CGPoint(x: width, y: (y - v0) / (v1 - v0) * gh))
        }
        ctx?.strokePath()
        
        var x0 = xOffset
        var lastRect = CGRect.zero
        bars.enumerated().forEach {
            let mark = marks.isEmpty || $0.offset >= marks.count ? Summary.Marks.none : marks[$0.offset]
            let barH = ($0.element - v0) / (v1 - v0) * gh
            let barRect = CGRect(x: x0, y: gh - barH, width: barWidth, height: barH)
            if mark.contains(Summary.Marks.red) {
                #colorLiteral(red: 0.5725490451, green: 0, blue: 0.2313725501, alpha: 1).setFill()
            } else {
                UIColor.blue.setFill()
            }
            ctx?.fill(barRect)
            if mark.contains(.seperator) {
                ctx?.move(to: CGPoint(x: x0 - spacing / 2, y: 0))
                ctx?.addLine(to: CGPoint(x: x0 - spacing / 2, y: gh))
                UIColor(white: 0.25, alpha: 1).setStroke()
                ctx?.strokePath()
            }
            x0 += barWidth + spacing
        }
        x0 = xOffset
        bars.enumerated().forEach {
            defer {
                x0 += barWidth + spacing
            }
            guard $0.element != 0 else {
                return
            }
            let barH = ($0.element - v0) / (v1 - v0) * gh
            let barRect = CGRect(x: x0, y: gh - barH, width: barWidth, height: barH)

            let textValue = "\(Double($0.element).decimal(digits: 1))".styled.color(.white).systemFont(size: 12)
            let size = textValue.size()
            var textRect = CGRect(x: barRect.midX - size.width / 2, y: gh - size.height , width: size.width, height: size.height)
            if textRect.maxY > h {
                textRect.origin.y = barRect.minY - size.height
            }
            if textRect.maxX > width {
                textRect.origin.x = width - size.width
            }
            if textRect.minX < 0 {
                textRect.origin.x = 0
            }
            if textRect.intersects(lastRect) {
                textRect.origin.y = lastRect.maxY
                if textRect.maxY > h {
                    textRect.origin.y = lastRect.minY - size.height
                }
                if textRect.origin.y < 0 {
                    textRect.origin.y = 0
                }
            }
            textValue.draw(in: textRect)
            
            lastRect = textRect

        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage(systemName: "chart.bar.fill")!
    }
}

#if DEBUG
struct BarView_Previews: PreviewProvider {
    static var previews: some View {
        BarView([113,114,113.5,113.6,116,111,119.5,118,119,118,106.5], marks: [.none, .none, .seperator, .none, .none, .none, .none, .none, .none, .none, .red ])
    }
   

}
#endif
