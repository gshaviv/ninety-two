//
//  PieChartView.swift
//  WoofWoof
//
//  Created by Guy on 29/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import SwiftUI

private struct Slice: Shape {
    let start: Angle
    let end: Angle
    
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: center)
        p.addArc(center: center, radius: r, startAngle: start - Angle(degrees: 90), endAngle: end - Angle(degrees: 90), clockwise: false)
        p.addLine(to: center)
        p.closeSubpath()
        return p
    }
}

struct ChartPiece {
    let value: Double
    let color: Color
}

struct PieChartView: View {
    private struct CumulativePiece: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
        let start: Double
    }
    private var pieces: [CumulativePiece]
    private var sum: Double
    
    public init(_ pieces: [ChartPiece]) {
        var cp = [CumulativePiece]()
        var sum:Double = 0
        for p in pieces {
            cp.append(CumulativePiece(value: p.value, color: p.color, start: sum))
            sum += p.value
        }
        self.pieces = cp
        self.sum = sum
    }
    
    var body: some View {
        ZStack {
            ForEach(self.pieces) { p in
                Slice(start: Angle(degrees: 360 * p.start / self.sum), end: Angle(degrees: ceil(360 * (p.start + p.value) / self.sum)))
                    .fill(p.color)
                Slice(start: Angle(degrees: 360 * p.start / self.sum), end: Angle(degrees: ceil(360 * (p.start + p.value) / self.sum)))
                    .stroke(Color.primary, lineWidth: 0.5)
            }
        }
    }
}

struct PieChartView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
        PieChartView([
            ChartPiece(value: 1, color: Color.red),
            ChartPiece(value: 2, color: Color.yellow),
            ChartPiece(value: 4, color: Color.green)
        ])
            Slice(start: Angle(degrees: 0), end: Angle(degrees: 120)).fill(Color.red)
        }
    }
}
