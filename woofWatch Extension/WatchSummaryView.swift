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
    var showEa1c: Action

    var body: some View {
        if summary.data.period == 0 {
            return VStack {
                ActivityIndicator(size: 40)
                Text("Fetching...").font(.headline)
            }
            .asAnyView
        } else {
            return List {
                Section(header: Text("Time In Range").font(.headline).foregroundColor(Color(white: 0.5))) {
                    Row(label: "Below", detail: "\(summary.data.percentTimeBelow.description)%")
                    Row(label: "In Range", detail: "\(summary.data.percentTimeIn.description)%")
                    Row(label: "Above", detail: "\(summary.data.percentTimeAbove.description)%")
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
                    Row(label: "Ave", detail: "\(summary.data.average % ".1lf")")
                    Button(action: { self.showEa1c.send() }) {
                        Row(label: "eA1C", detail: summary.data.a1c.range > 0.05 ? "\(summary.data.a1c.value % ".1lf") ± \(summary.data.a1c.range % ".1lf")" : "\(summary.data.a1c.value % ".1lf")")
                    }
                    
                    Row(label: "# Lows", detail: "\(summary.data.low.count)")
                    Row(label: "Median Low", detail: summary.data.low.median < 60 ? String(format: "%ldm", summary.data.low.median) : String(format: "%ld:%02ld",summary.data.low.median / 60, summary.data.low.median % 60))
                    Row(label: "Min", detail: "\(summary.data.minLevel % ".0lf")")
                    Row(label: "Max", detail: "\(summary.data.maxLevel % ".0lf")")
                    Row(label: "TDD", detail: "\(summary.data.atdd % ".1lf")")
                }
            }.asAnyView
        }
    }
}

struct Row: View {
    let label: String
    let detail: String
    var body: some View {
        HStack {
            Text("\(label):").headline()
            Spacer(minLength: 12)
            Text(detail).value()
        }
    }
}

class WatchSummaryController: WKHostingController<AnyView> {
    var summaryObserver: AnyCancellable?
    var showObserver: AnyCancellable?
    
    override var body: AnyView {
        let show = Action()
        showObserver = show.sink(receiveValue: {
            self.showEa1c()
        })
        return WatchSummaryView(summary: summary, showEa1c: show).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        summaryObserver = summary.$data.sink(receiveValue: { [weak self] (data) in
            if data.period > 0 {
                self?.setTitle("\(data.period == 1 ? 24 : data.period) \(data.period > 1 ? "Days" : "Hours")")
            }
        })
        if summary.data.period == 0 || Date() - summary.calcDate > 90.m {
            WCSession.default.sendMessage(["op":["summary"]], replyHandler: ExtensionDelegate.replyHandler(_:), errorHandler: { _ in })
        }
    }
    
    func showEa1c() {
        pushController(withName: "ea1c", context: nil)
    }
}

#if DEBUG
struct WatchSummaryView_Previews: PreviewProvider {
    static var platform: PreviewPlatform? = .watchOS
    static let summary = SummaryInfo(Summary(period: 30, timeInRange: Summary.TimeInRange(low: 30, inRange: 30, high: 30), maxLevel: 246, minLevel: 45, average: 125, a1c: Summary.EA1C(value: 6.1, range: 0.1), low: Summary.Low(count: 20, median: 45), atdd: 20.1, timeInLevel: [5,5,40,40,40,10,10]))
    static var previews: some View {
        WatchSummaryView(summary: summary, showEa1c: Action())
    }
}
#endif
