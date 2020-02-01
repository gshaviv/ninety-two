//
//  GlucoseFace.swift
//  woofWatch Extension
//
//  Created by Guy on 17/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import WatchKit
import SwiftUI
import Combine

struct GlucoseFace: View {
    @EnvironmentObject var state: AppState
    @State var showPercentage = false
    
    var body: some View {
        guard let last = state.data.readings.last else {
            return VStack {
                ActivityIndicator(size: 40)
                Text("Connecting...").font(.headline)
            }
            .asAnyView
        }
        let levelStr = last.value > 70 ? String(format: "%.0lf", last.value) : String(format: "%.1lf", last.value)
        let tvalue: String
        if state.state == .error {
            tvalue = " ❌ "
        } else if last.value < 70 {
            tvalue = "\(state.data.trendValue > 0 ? "+" : "")\(String(format: "%.1lf",state.data.trendValue).trimmingCharacters(in: CharacterSet(charactersIn: "0")))"
        } else {
            tvalue = String(format: "%@%.1lf", state.data.trendValue > 0 ? "+" : "", state.data.trendValue)
        }
        
        return
            VStack(alignment: HorizontalAlignment.center, spacing: 2) {
                HStack(alignment: .center, spacing: 0) {
                    if !showPercentage {
                        Image(uiImage: batteryLevelIcon(for: state.data.batteryLevel)).onTapGesture {
                            self.showPercentage = true
                        }
                    } else {
                        Text("\(state.data.batteryLevel)%").font(Font.system(.caption)).onAppear {
                            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(3)) {
                                self.showPercentage = false
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if state.state == .sending {
                        ActivityIndicator(size: 14).padding(.leading, 2)
                    } else {
                        Text(tvalue)
                            .lineLimit(1)
                            .layoutPriority(0)
                    }
                    Spacer(minLength: 0)
                    Text("\(levelStr)\(state.data.trendSymbol)")
                        .font(.title)
                        .foregroundColor(state.state == .error ? .pink : .yellow)
                        .lineLimit(1)
                        .layoutPriority(2)
                    
                }
                GeometryReader { geometry in
                    GraphImage(state: self.state, size: geometry.size)
                        .cornerRadius(8)
                }.padding([.bottom], 2)
            }
            .edgesIgnoringSafeArea([.bottom, .leading, .trailing])
            .asAnyView
    }
    
    private func batteryLevelIcon(for level: Int) -> UIImage {
        let frac = CGFloat(level) / 100
        let color = UIColor(white: 0.2 + 0.7 * (1 - (1 - frac) * (1 - frac)), alpha: 1)
        
        switch level {
        case 90...:
            return UIImage(named: "battery-5")!.tint(with: color)
            
        case 60..<90:
            return UIImage(named: "battery-4")!.tint(with: color)
            
        case 30..<60:
            return UIImage(named: "battery-3")!.tint(with: color)
            
        case 20..<30:
            return UIImage(named: "battery-2")!.tint(with: color)
            
        case 0 ..< 20:
            return UIImage(named: "battery-1")!.tint(with: color)
            
        default:
            return UIImage(systemName: "questionmark.square.fill")!.tint(with: .red)
        }
    }
}

extension View {
    /// Returns a type-erased version of the view.
    public var asAnyView: AnyView { AnyView(self) }
}



#if DEBUG
struct GlucoseFace_Previews: PreviewProvider {
    static func GenerateReadings() -> (trend:[GlucosePoint], history:[GlucosePoint]) {
        var history = [GlucosePoint]()
        var trend = [GlucosePoint]()
        var value = 65.0 // Double.random(in: 70 ... 180)
        var when = Date() - 1.m - 30.s
        var valueTrend = 1.0 // Double.random(in: 0 ..< 1) > 0.5 ? 1.0 : -1.0
        for _ in 0 ..< 5 {
            trend.insert(GlucosePoint(date: when, value: value), at: 0)
            when -= 3.m
            if value > 180.0 {
                valueTrend = -1.0
            } else if value < 75.0 {
                valueTrend = 1.0
            }
            value += valueTrend * Double.random(in: 0 ... 2)
        }
        for _ in 0 ..< 12 {
            history.insert(GlucosePoint(date: when, value: value), at: 0)
            when -= 15.m
            if value > 180.0 {
                valueTrend = -1.0
            } else if value < 75.0 {
                valueTrend = 1.0
            }
            value += valueTrend * Double.random(in: 1 ... 10)
        }
        return (trend, history)
    }
    
    static let testState: AppState = {
        let state = AppState()
        let readings = GenerateReadings()
        state.data = StateData(trendValue: 0.1, trendSymbol: "→", trend: readings.trend, history: readings.history, events: [Event(date: (Date() - 1.h).timeIntervalSince1970, bolus: 6)],  sensorBegin: Date() - 7.d - 4.h, batteryLevel: 80)
        return state
    }()
    
    static let errorState: AppState = {
        let state = AppState()
        let readings = GenerateReadings()
        state.data = StateData(trendValue: 0.1, trendSymbol: "→", trend: readings.trend, history: readings.history, events: [Event(date: (Date() - 1.h).timeIntervalSince1970, bolus: 3)],  sensorBegin: Date() - 13.d - 2.h, batteryLevel: 70)
        state.state = .error
        return state
    }()
    
    static let sendingState: AppState = {
        let state = AppState()
        let readings = GenerateReadings()
        state.data = StateData(trendValue: 0.1, trendSymbol: "→", trend: readings.trend, history: readings.history, events: [], sensorBegin: Date() - 14.d, batteryLevel: 60)
        state.state = .sending
        return state
    }()
    
    static let snapshotState: AppState = {
        let state = AppState()
        let readings = GenerateReadings()
       state.data = StateData(trendValue: 0.1, trendSymbol: "→", trend: readings.trend, history: readings.history, events: [], sensorBegin: Date() - 14.d, batteryLevel: 30)
        state.state = .snapshot
        return state
    }()
    
    static let initialState = AppState()

    static var previews: some View {
        Group {
            GlucoseFace().previewDisplayName("Normal").environmentObject(testState)
            GlucoseFace().previewDisplayName("Error").environmentObject(errorState)
            GlucoseFace().previewDisplayName("Sending").environmentObject(sendingState)
            GlucoseFace().previewDisplayName("Snapshot").environmentObject(snapshotState)
            GlucoseFace().previewDisplayName("Initial").environmentObject(initialState)
        }
    }
}

#endif
