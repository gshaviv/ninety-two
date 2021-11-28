//
//  SiriIntentView.swift
//  SiriIntentUI
//
//  Created by Guy on 27/11/2021.
//  Copyright © 2021 TivStudio. All rights reserved.
//

import SwiftUI
import WoofKit

class WidgetState: ObservableObject {
    @Published var points = [GlucosePoint]()
    @Published var records = [Entry]()
    @Published var date =  Date.distantPast
}

struct BGStatusView : View {
    @ObservedObject var entry: WidgetState
    @Environment(\.colorScheme) var colorScheme
    enum SizeClass {
        case small
        case medium
        case large
    }
    var sizeClass: SizeClass
    
    private var levelString: String {
        guard let current = entry.points.last, entry.points.count > 1 else {
            return "?"
        }
        let previous = entry.points[entry.points.count - 2]
        let trend = (current.value - previous.value) / (current.date > previous.date ? current.date - previous.date : previous.date - current.date) * 60
        let symbol = trendSymbol(for: trend)
        return "\(current.value % "%.0lf")\(symbol)"
    }
    
    private var trend: String {
        guard let current = entry.points.last, entry.points.count > 3 else {
            return ""
        }
        let previous = entry.points[entry.points.count - (current.value > 70 ? 4 : 2)]
        let trend = (current.value - previous.value) / abs(current.date - previous.date) * 60
        return "\(trend % ".1lf")"
    }
    
    
    private var levelFont: Font {
        switch sizeClass {
        case .small:
            return Font.system(size: 20, weight: .bold, design: Font.Design.default)
        case .medium:
            return Font.system(size: 25, weight: .bold, design: Font.Design.default)
        case .large:
            return Font.system(size: 36, weight: .black, design: Font.Design.default)
        }
    }
    
    private var TimeIndicator: some View {
        if Date() - entry.date < 1.h {
            return Text(entry.date, style: .timer)
        } else {
            return Text(">\(Int((Date()-entry.date)/1.h))h")
        }
    }
    
    let iob = Storage.default.insulinOnBoard(at: Date())
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                TimeIndicator
                    .lineLimit(1)
                    .font(Font.monospacedDigit(sizeClass == .small ? Font.system(size: 11) : Font.system( .caption))())
                    .minimumScaleFactor(0.5)
                
                if iob > 0 {
                    Text("BOB\n\(iob % ".1lf")")
                        .lineLimit(2)
                        .font(Font.monospacedDigit(sizeClass == .small ? Font.system(size: 11) : Font.system( .caption))())
                        .multilineTextAlignment(.center)
                        .layoutPriority(2)
                        .minimumScaleFactor(0.75)
                } else {
                    Text("\n")
                        .lineLimit(2)
                        .font(Font.monospacedDigit(sizeClass == .small ? Font.system(size: 11) : Font.system( .caption))())
                }
                
                Spacer()
                
                Text(trend)
                    .font(Font.system(.caption))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                
                Text(levelString)
                    .font(levelFont)
                    .lineLimit(1)
                    .layoutPriority(3)
            }
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .layoutPriority(4)
            
            if entry.points.isEmpty {
                EmptyView()
            } else {
                BGWidgetGraph(points: entry.points, records: entry.records , hours:  sizeClass == .small ? 2 : 3.5, cornerRatio: 0.12)
                    .frame( maxWidth: .infinity,  maxHeight: .infinity)
            }
        }
        .background(colorScheme == .light ? Color(.lightGray) : Color(.darkGray))
    }
}

