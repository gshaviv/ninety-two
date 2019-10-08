//
//  WatchSummaryView.swift
//  woofWatch Extension
//
//  Created by Guy on 30/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import SwiftUI
import WatchConnectivity
import Combine

extension Text {
    func headline() -> some View {
            self
                .font(.headline)
                .foregroundColor(Color.white)
    }
    func value() -> some View {
        self
            .font(.body)
            .foregroundColor(Color.yellow)
    }
}

struct WatchSummaryView: View {
    @ObservedObject var summary: SummaryInfo

    var body: some View {
        if summary.data.period == 0 || Date() - summary.calcDate > 2.h {
            WCSession.default.sendMessage(["op":["summary"]], replyHandler: WCSession.replyHandler(_:), errorHandler: { _ in })
        }
        if summary.data.period == 0 {
            return VStack {
                ActivityIndicator(size: 40)
                Text("Fetching...").font(.headline)
            }
            .asAnyView
        } else {
            return List {
                Section(header: Text("Time In Range").font(.headline).foregroundColor(Color(white: 0.5))) {
                    HStack {
                        Text("Below:").headline()
                        Spacer(minLength: 12)
                        Text("\(summary.data.percentTimeBelow.description)%").value()
                    }
                    HStack {
                        Text("In Range:").headline()
                        Spacer(minLength: 12)
                        Text("\(summary.data.percentTimeIn.description)%").value()
                    }
                    HStack {
                        Text("Above:").headline()
                        Spacer(minLength: 12)
                        Text("\(summary.data.percentTimeAbove.description)%").value()
                    }
                    PieChartView([
                        ChartPiece(value: summary.data.timeInLevel[2], color: Color(defaults[.color2])),
                        ChartPiece(value: summary.data.timeInLevel[3], color: Color(defaults[.color3])),
                        ChartPiece(value: summary.data.timeInLevel[4], color: Color(defaults[.color4])),
                        ChartPiece(value: summary.data.timeInLevel[5], color: Color(defaults[.color5])),
                        ChartPiece(value: summary.data.timeInLevel[1], color: Color(defaults[.color1])),
                        ChartPiece(value: summary.data.timeInLevel[0], color: Color(defaults[.color0])),
                    ]).aspectRatio(1, contentMode: .fit)
                        .padding(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                Section(header: Text("Statistics").font(.headline).foregroundColor(Color(white: 0.5))) {
                    HStack {
                        Text("Ave:").headline()
                        Spacer(minLength: 12)
                        Text("\(summary.data.average, specifier:"%.1lf")").value()
                    }
                    HStack {
                        Text("eA1C:").headline()
                        Spacer(minLength: 12)
                        Text(summary.data.a1c.range > 0.05 ? "\(summary.data.a1c.value, specifier:"%.1lf") ± \(summary.data.a1c.range, specifier:"%.1lf")" : "\(summary.data.a1c.value, specifier:"%.1lf")").value()
                    }
                    HStack {
                        Text("# Lows:").headline()
                        Spacer(minLength: 12)
                        Text("\(summary.data.low.count)").value()
                    }
                    HStack {
                        Text("Median Low:").headline()
                        Spacer(minLength: 12)
                        Text(summary.data.low.median < 60 ? String(format: "%ldm", summary.data.low.median) : String(format: "%ld:%02ld",summary.data.low.median / 60, summary.data.low.median % 60)).value()
                    }
                    HStack {
                        Text("Min:").headline()
                        Spacer(minLength: 12)
                        Text("\(summary.data.minLevel, specifier:"%.0lf")").value()
                    }
                    HStack {
                        Text("Max:").headline()
                        Spacer(minLength: 12)
                        Text("\(summary.data.maxLevel, specifier:"%.0lf")").value()
                    }
                    HStack {
                        Text("TDD:").headline()
                        Spacer(minLength: 12)
                        Text("\(summary.data.atdd, specifier:"%.1lf")").value()
                    }
                }
            }.asAnyView
        }
    }
}

class WatchSummaryController: WKHostingController<AnyView> {
    var summaryObserver: AnyCancellable?
    
    override var body: AnyView {
        WatchSummaryView(summary: summary).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        summaryObserver = summary.$data.sink(receiveValue: { [weak self] (data) in
            if data.period > 0 {
                self?.setTitle("\(data.period == 1 ? 24 : data.period) \(data.period > 1 ? "Days" : "Hours")")
            }
        })
    }
}

#if DEBUG
struct WatchSummaryView_Previews: PreviewProvider {
    static var platform: PreviewPlatform? = .watchOS
    static let summary = SummaryInfo(Summary(period: 30, timeInRange: Summary.TimeInRange(low: 30, inRange: 30, high: 30), maxLevel: 246, minLevel: 45, average: 125, a1c: Summary.EA1C(value: 6.1, range: 0.1), low: Summary.Low(count: 20, median: 45), atdd: 20.1, timeInLevel: [5,5,40,40,40,10,10]))
    static var previews: some View {
        WatchSummaryView(summary: summary)
    }
}
#endif
