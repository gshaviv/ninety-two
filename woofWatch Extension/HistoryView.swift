//
//  DoseHistoryView.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2020.
//  Copyright © 2020 TivStudio. All rights reserved.
//

import SwiftUI
import Combine

struct DoseHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo

    var body: some View {
        VStack {
            Text("Daily Dosages").font(Font.system(.headline))
        BarView(summary.data.daily.map { $0.dose }, marks: summary.data.daily.map { [$0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none, $0.date.isOnSameDay(as: Date()) ? Summary.Marks.blue : Summary.Marks.none ] })
        }
    }
}

struct AveHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo
    
    var body: some View {
        VStack {
            Text("Daily Averages").font(Font.system(.headline))
        BarView(summary.data.daily.map { rint($0.average) }, marks: summary.data.daily.map { [$0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none, $0.date.isOnSameDay(as: Date()) ? Summary.Marks.blue : Summary.Marks.none ] })
        }
    }
}

class WatchDoseController: WKHostingController<AnyView> {
    override var body: AnyView {
        return DoseHistoryView().environmentObject(summary).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        setTitle("Summary")
    }
}

class WatchAveHistoryController: WKHostingController<AnyView> {    
    override var body: AnyView {
        return AveHistoryView().environmentObject(summary).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        setTitle("Summary")
    }
}


struct DoseHistoryView_Previews: PreviewProvider {
    static let summary = SummaryInfo(Summary(period: 30, timeInRange: Summary.TimeInRange(low: 30, inRange: 30, high: 30), maxLevel: 246, minLevel: 45, average: 125, a1c: Summary.EA1C(value: 6.1, range: 0.1), low: Summary.Low(count: 20, median: 45), atdd: 20.1, timeInLevel: [5,5,40,40,40,10,10], daily: [Summary.Daily(average: 120.0, dose: 20, date: Date() - 7.d),Summary.Daily(average: 120.5, dose: 18, date: Date() - 6.d),Summary.Daily(average: 123.0, dose: 22, date: Date() - 5.d),Summary.Daily(average: 120.0, dose: 17, date: Date() - 4.d),Summary.Daily(average: 113.4, dose: 16, date: Date() - 3.d),Summary.Daily(average: 117.4, dose: 19, date: Date() - 2.d),Summary.Daily(average: 114.4, dose: 21, date: Date() - 1.d),Summary.Daily(average: 120.0, dose: 8, date: Date())]))

    static var previews: some View {
        DoseHistoryView().environmentObject(summary)
    }
}
