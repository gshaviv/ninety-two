//
//  TimeLabel.swift
//  woofWatch Extension
//
//  Created by Guy on 20/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import SwiftUI

struct TimeLabel: View {
    @EnvironmentObject var currentTime: CurrentTime
    var last: GlucosePoint
    
    var body: some View {
        let seconds = Int(currentTime.value.timeIntervalSince(last.date))
        let timeStr: String
        if seconds < 0 {
            timeStr = "   "
        } else if last.value < 70 {
            timeStr = (seconds < 90 ? String(format: "%02ld", seconds) : String(format: "%ld:%02ld", seconds / 60, seconds % 60))
        } else {
            timeStr = String(format: "%ld:%02ld", seconds / 60, seconds % 60)
        }
        
        return Text(timeStr)
            .font(Font.body.monospacedDigit().bold())
            .lineLimit(1)
    }
}

