//
//  SummaryView.swift
//  WoofWoof
//
//  Created by Guy on 29/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import SwiftUI
import WoofKit
import Combine



extension Text {
    func headline() -> some View {
        return GeometryReader { g in
            self
                .font(.headline)
                .frame(width: g.size.width)
                .background(Color.headlineBackground)
        }
    }
    func value() -> some View {
        return self
            .font(.body)
//            .foregroundColor(Color.yellow)
    }
}

typealias Action = PassthroughSubject<Void,Never>

struct SummaryView: View {
    @ObservedObject var summary: SummaryInfo
    let action: Action
    
    var body: some View {
        VStack {
            Text("Last \(summary.data.period == 1 ? 24 : summary.data.period) \(summary.data.period > 1 ? "Days" : "Hours")").font(.headline).onTapGesture {
                self.action.send()
            }
            BalancedHStack(spacing: 2) {
                PieChartView([
                    ChartPiece(value: summary.data.timeInLevel[2], color: Color(defaults[.color2])),
                    ChartPiece(value: summary.data.timeInLevel[3], color: Color(defaults[.color3])),
                    ChartPiece(value: summary.data.timeInLevel[4], color: Color(defaults[.color4])),
                    ChartPiece(value: summary.data.timeInLevel[5], color: Color(defaults[.color5])),
                    ChartPiece(value: summary.data.timeInLevel[1], color: Color(defaults[.color1])),
                    ChartPiece(value: summary.data.timeInLevel[0], color: Color(defaults[.color0])),
                ])
                VStack {
                    Text("% Low").headline()
                    Text("\(summary.data.percentTimeBelow.description)%").value()
                    Text("# Lows").headline()
                    Text("\(summary.data.low.count)").value()
                    Text("Med Low").headline()
                    Text(summary.data.low.median < 60 ? String(format: "%ldm", summary.data.low.median) : String(format: "%ld:%02ld",summary.data.low.median / 60, summary.data.low.median % 60)).value()
                }
                VStack {
                    Text("In Range").headline()
                    Text("\(summary.data.percentTimeIn.description)%").value()
                    Text("Ave").headline()
                    Text("\(summary.data.average % ".0lf")").value()
                    Text("A1C").headline()
                    Text("\(summary.data.a1c % ".1lf")").value()
                }
                VStack {
                    Text("% High").headline()
                    Text("\(summary.data.percentTimeAbove.description)%").value()
                    Text("Min / Max").headline()
                    Text("\(summary.data.minLevel % ".0lf") / \(summary.data.maxLevel % ".0lf")").value()
                    Text("Ave TDD").headline()
                    Text("\(summary.data.atdd % ".1lf")").value()
                }
            }
        }
    }
}

#if DEBUG
struct SummaryView_Previews: PreviewProvider {
    static let summary = SummaryInfo(Summary(period: 30, timeInRange: Summary.TimeInRange(low: 30, inRange: 30, high: 30), maxLevel: 246, minLevel: 45, average: 125, a1c: 6.0, low: Summary.Low(count: 20, median: 45), atdd: 20.1, timeInLevel: [5,5,40,40,40,10,10]))
    static var previews: some View {
        Group {
            SummaryView(summary: summary, action: Action()).previewLayout(PreviewLayout.fixed(width: 375, height: 175))
            SummaryView(summary: summary, action: Action()).previewLayout(PreviewLayout.fixed(width: 375, height: 175)).environment(\.colorScheme, .dark).background(Color.black)
        }
    }
    static var platform: PreviewPlatform? = .iOS
}
#endif
