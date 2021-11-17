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
import UIKit

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
    var actions: Action<SummaryAction>
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
                    HStack {
                        PieChartView([
                            ChartPiece(value: summary.data.timeInLevel[2], color: Color(defaults[.color2])),
                            ChartPiece(value: summary.data.timeInLevel[3], color: Color(defaults[.color3])),
                            ChartPiece(value: summary.data.timeInLevel[4], color: Color(defaults[.color4])),
                            ChartPiece(value: summary.data.timeInLevel[5], color: Color(defaults[.color5])),
                            ChartPiece(value: summary.data.timeInLevel[1], color: Color(defaults[.color1])),
                            ChartPiece(value: summary.data.timeInLevel[0], color: Color(defaults[.color0])),
                        ]).aspectRatio(1, contentMode: .fit)
                            .padding(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        Image(systemName: "chevron.right").font(Font.system(size: 12))
                    }.onTapGesture {
                        self.actions.send(.rangeHistory)
                    }
                }
                Section(header: Text("Statistics").font(.headline).foregroundColor(Color(white: 0.5))) {
                    Button(action: { self.actions.send(.ave) }) {
                        Row(label: "Ave", detail: "\(summary.data.average % ".1lf")", disclosureIndicator: true)
                    }
                    Button(action: { self.actions.send(.ea1c) }) {
                        Row(label: "eA1C", detail: summary.data.a1c.range > 0.05 ? "\(summary.data.a1c.value % ".1lf") ± \(summary.data.a1c.range % ".1lf")" : "\(summary.data.a1c.value % ".1lf")", disclosureIndicator: true)
                    }
                    
                    Button(action: { self.actions.send(.lows) }) {
                        Row(label: "# Lows", detail: "\(summary.data.low.count)", disclosureIndicator: true)
                    }
                    Row(label: "Median Low", detail: summary.data.low.median < 60 ? String(format: "%ldm", summary.data.low.median) : String(format: "%ld:%02ld",summary.data.low.median / 60, summary.data.low.median % 60))
                    Row(label: "Min", detail: "\(summary.data.minLevel % ".0lf")")
                    Row(label: "Max", detail: "\(summary.data.maxLevel % ".0lf")")
                    Button(action: { self.actions.send(.dose) }) {
                        Row(label: "TDD", detail: "\(summary.data.atdd % ".1lf")", disclosureIndicator: true)
                    }
                }
                Section(header: Text("Data as of:").font(.headline).foregroundColor(Color(white: 0.5))) {
                    Text(summary.data.dateString)
                }
            }.asAnyView
        }
    }
}

struct Row: View {
    let label: String
    let detail: String
    let chevron: Bool
    
    init(label: String, detail: String, disclosureIndicator: Bool = false) {
        self.label = label
        self.detail = detail
        chevron = disclosureIndicator
    }
    
    var body: some View {
        HStack {
            Text("\(label):").headline()
            Spacer(minLength: 12)
            Text(detail).value()
            if chevron {
                Image(systemName: "chevron.right").font(Font.system(size: 8))
            } else {
                Image(systemName: "chevron.right").font(Font.system(size: 8)).hidden()
            }
        }
    }
}

enum SummaryAction: String {
    case ea1c
    case dose
    case ave
    case lows
    case rangeHistory
}

class WatchSummaryController: WKHostingController<AnyView> {
    var summaryObserver: AnyCancellable?
    
    override var body: AnyView {
        let show = Action<SummaryAction>()
        summaryObserver = show.sink { [weak self] in
            switch $0 {
            case .ea1c, .dose, .ave, .lows, .rangeHistory:
                self?.pushController(withName: $0.rawValue, context: nil)
            }
        }
        
        return WatchSummaryView(summary: summary, actions: show).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        summaryObserver = summary.$data.sink(receiveValue: { [weak self] (data) in
            if data.period > 0 {
                self?.setTitle("\(data.actualPeriod == 1 ? 24 : data.actualPeriod) \(data.actualPeriod > 1 ? "Days" : "Hours")")
            }
        })
        if summary.data.period == 0 || Date() - summary.data.date > 1.h {
            WCSession.default.sendMessage(["op":["summary"]], replyHandler: ExtensionDelegate.replyHandler(_:), errorHandler: { _ in })
        }
    }
}

#if DEBUG
struct WatchSummaryView_Previews: PreviewProvider {
    static var platform: PreviewPlatform? = .watchOS
    static let summary = SummaryInfo(Summary(period: 30, actualPeriod: 30, timeInRange: Summary.TimeInRange(low: 30, inRange: 30, high: 30), maxLevel: 246, minLevel: 45, average: 125, a1c: Summary.EA1C(value: 6.1, range: 0.1), low: Summary.Low(count: 20, median: 45), atdd: 20.1, timeInLevel: [5,5,40,40,40,10,10], daily: [], date: Date()))
    static var previews: some View {
        WatchSummaryView(summary: summary, actions: Action<SummaryAction>())
    }
}
#endif
