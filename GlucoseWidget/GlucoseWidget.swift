//
//  GlucoseWidget.swift
//  GlucoseWidget
//
//  Created by Guy on 28/09/2020.
//  Copyright © 2020 TivStudio. All rights reserved.
//

import WidgetKit
import SwiftUI
import Intents
import WoofKit
import GRDB
import Foundation

private let sharedDbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "5h.sqlite"))

class Provider: NSObject, IntentTimelineProvider {
    

    
    func placeholder(in context: Context) -> BGEntry {
        BGEntry(date: Date(), configuration: ConfigurationIntent(), points: [], records: [])
    }

    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (BGEntry) -> ()) {
        readData { (points, records) in
            let entryDate = points.last?.date ?? Date()
            let entry = BGEntry(date: entryDate, configuration: configuration, points: points, records: records)
            completion(entry)
        }
    }

    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<BGEntry>) -> ()) {
        readData { (points, records) in
            let entryDate = points.last?.date ?? Date()
            let timeline = Timeline(entries: [
                BGEntry(date: entryDate, configuration: configuration, points: points, records: records)
            ], policy: .after(entryDate + 15.m))
            completion(timeline)
        }
    }
    
    private func readData(completion: @escaping ([GlucosePoint], [Entry]) -> Void) {
        DispatchQueue.global().async {
            do {
                let p = try Storage.default.db.read {
                    try GlucosePoint.filter(GlucosePoint.Column.date > Date() - 5.h).fetchAll($0)
                } + Storage.default.trendDb.read {
                    try GlucosePoint.fetchAll($0)
                }
                Storage.default.reloadToday()
                let records = Storage.default.lastDay.entries
                completion(p.sorted(by: { $0.date < $1.date }), records)
            } catch {
                logError("Error reading: \(error.localizedDescription)")
                completion([], [])
            }
        }
    }
}


struct BGEntry: TimelineEntry {
    public let date: Date
    public let configuration: ConfigurationIntent
    public let points: [GlucosePoint]
    public let records: [Entry]
}


struct GlucoseWidgetEntryView : View {
    var entry: BGEntry
    var status: WidgetState  {
        let s = WidgetState()
        s.points = entry.points
        s.records = entry.records
        s.date = entry.date
        return s
    }
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        BGStatusView(entry: status, sizeClass: {
            switch family {
            case .systemSmall:
                return .small
                
            case .systemMedium:
                return .medium
                
            default:
                return .large
            }
        }())
        .background(colorScheme == .light ? Color(.lightGray) : Color(.darkGray))
    }
}

@main
struct GlucoseWidget: Widget {
    let kind: String = "GlucoseWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: Provider()) { entry in
            GlucoseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("BG Widget")
        .description("Blood glucose widget.")
    }
}

struct GlucoseWidget_Previews: PreviewProvider {
    static let points = [
        GlucosePoint(date: Date() - 120.m, value: 127),
        GlucosePoint(date: Date() - 105.m, value: 123),
        GlucosePoint(date: Date() - 90.m, value: 112),
        GlucosePoint(date: Date() - 75.m, value: 97),
        GlucosePoint(date: Date() - 60.m, value: 83),
        GlucosePoint(date: Date() - 45.m, value: 95),
        GlucosePoint(date: Date() - 30.m, value: 90),
        GlucosePoint(date: Date() - 15.m, value: 82),
        GlucosePoint(date: Date(), value: 80)
    ]
    static var previews: some View {
        Group {
            GlucoseWidgetEntryView(entry: BGEntry(date: Date() - 46.s, configuration: ConfigurationIntent(), points: GlucoseWidget_Previews.points, records: []))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            GlucoseWidgetEntryView(entry: BGEntry(date: Date() - 46.s, configuration: ConfigurationIntent(), points: GlucoseWidget_Previews.points, records: []))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            
            GlucoseWidgetEntryView(entry: BGEntry(date: Date() - 46.s, configuration: ConfigurationIntent(), points: GlucoseWidget_Previews.points, records: []))
                .previewContext(WidgetPreviewContext(family: .systemLarge))
            
            GlucoseWidgetEntryView(entry: BGEntry(date: Date() - 46.s, configuration: ConfigurationIntent(), points: GlucoseWidget_Previews.points, records: []))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .environment(\.colorScheme, .dark)
        }
    }
}
