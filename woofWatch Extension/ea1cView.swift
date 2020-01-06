//
//  ea1cView.swift
//  woofWatch Extension
//
//  Created by Guy on 08/10/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import SwiftUI

struct Ea1cView: View {
    @ObservedObject var summary: SummaryInfo

    var body: some View {
        List {
            Row(label: "CGM", detail: "\(summary.data.a1c.cgm % ".1lf")")
            Row(label: "7 Profile", detail: "\(summary.data.a1c.seven % ".1lf")")
            Row(label: "TIR", detail: "\(summary.data.a1c.tir % ".1lf")")
        }
    }
}

class EA1CController: WKHostingController<AnyView> {
    
    override var body: AnyView {
        return Ea1cView(summary: summary).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
    }
}

#if DEBUG
struct ea1cView_Previews: PreviewProvider {
    static var platform: PreviewPlatform? = .watchOS
    static let summary = SummaryInfo(Summary(period: 30, timeInRange: Summary.TimeInRange(low: 30, inRange: 30, high: 30), maxLevel: 246, minLevel: 45, average: 125, a1c: Summary.EA1C(value: 6.1, range: 0.1), low: Summary.Low(count: 20, median: 45), atdd: 20.1, timeInLevel: [5,5,40,40,40,10,10], daily: []))
    static var previews: some View {
        Ea1cView(summary: summary)
    }
}
#endif
