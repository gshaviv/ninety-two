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
    @ObservedObject var state: AppState
    @ObservedObject var currentTime: CurrentTime
    
    var body: some View {
        guard let last = state.data.readings.last else {
            return AnyView(Text("No Data"))
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
        
        let seconds = Int(currentTime.value.timeIntervalSince(last.date))
        let timeStr: String
        if last.value < 70 {
            timeStr = (seconds < 90 ? String(format: "%02ld", seconds) : String(format: "%ld:%02ld", seconds / 60, seconds % 60))
        } else {
            timeStr = String(format: "%ld:%02ld", seconds / 60, seconds % 60)
        }
        
        return
            AnyView(
                VStack(alignment: HorizontalAlignment.center, spacing: 2) {
                    HStack(alignment: .center, spacing: 0) {
                        if state.state == .sending {
                            CircularActivityIndicator(size: 14).padding(.leading, 2)
                        } else {
                            Text(tvalue)
                                .multilineTextAlignment(.leading)
                                .lineLimit(1)
                                .layoutPriority(0)
                        }
                        Spacer(minLength: 0)
                        Text("\(levelStr)\(state.data.trendSymbol)")
                            .font(.title)
                            .foregroundColor(state.state == .error ? .pink : .yellow)
                            .lineLimit(1)
                            .layoutPriority(2)
                        Spacer(minLength: 0)
                        Text(timeStr)
                            .font(Font.body.monospacedDigit().bold())
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    GeometryReader { geometry in
                        GraphImage(state: self.state, size: geometry.size)
                    }
                }.edgesIgnoringSafeArea([.bottom, .leading, .trailing])
        )
    }
}



#if DEBUG
let testState: AppState = {
    let state = AppState()
    var readings = [GlucosePoint]()
    var value = Double.random(in: 70 ... 180)
    var when = Date() - 1.m - 30.s
    var trend = Double.random(in: 0 ..< 1) > 0.5 ? 1.0 : -1.0
    for _ in 0 ..< 10 {
        readings.insert(GlucosePoint(date: when, value: value), at: 0)
        when -= 15.m
        if value > 180.0 {
            trend = -1.0
        } else if value < 75.0 {
            trend = 1.0
        }
        value += trend * Double.random(in: 1 ... 10)
    }
    
    state.data = StateData(trendValue: 0.1, trendSymbol: "→", readings: readings, iob: 0, insulinAction: 0)
    return state
}()

let errorState: AppState = {
    let state = AppState()
    state.data = testState.data
    state.state = .error
    return state
}()

let sendingState: AppState = {
    let state = AppState()
    state.data = testState.data
    state.state = .sending
    return state
}()

let time = CurrentTime()

struct GlucoseFace_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            GlucoseFace(state: testState, currentTime: time)
            GlucoseFace(state: errorState, currentTime: time)
            GlucoseFace(state: sendingState, currentTime: time)
        }
    }
}

#endif
