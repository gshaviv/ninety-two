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
import Sqlable
import Foundation

private let sharedDbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "5h.sqlite"))

class Provider: NSObject, IntentTimelineProvider {
    lazy private var coordinator: NSFileCoordinator = {
        NSFileCoordinator(filePresenter: self)
    }()
    private let sharedDb: SqliteDatabase? = {
        defaults.register()
        let db = try? SqliteDatabase(filepath: sharedDbUrl.path)
        return db
    }()
    
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

    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        readData { (points, records) in
            let entryDate = points.last?.date ?? Date()
            let timeline = Timeline(entries: [
                BGEntry(date: entryDate, configuration: configuration, points: points, records: records)
            ], policy: .after(entryDate + 15.m))
            completion(timeline)
        }
    }
    
    private func readData(completion: @escaping ([GlucosePoint], [Record]) -> Void) {
        DispatchQueue.global().async {
            self.coordinator.coordinate(readingItemAt: sharedDbUrl, error: nil, byAccessor: { (_) in
                if let p = self.sharedDb?.evaluate(GlucosePoint.read()) {
                    Storage.default.reloadToday()
                    let records = Storage.default.lastDay.entries
                    completion(p.sorted(by: { $0.date < $1.date }), records)
                } else {
                    completion([], [])
                }
            })
        }
    }
}

extension Provider: NSFilePresenter {
    var presentedItemURL: URL? {
        return sharedDbUrl
    }
    
    var presentedItemOperationQueue: OperationQueue {
        return OperationQueue.main
    }
}

struct BGEntry: TimelineEntry {
    public let date: Date
    public let configuration: ConfigurationIntent
    public let points: [GlucosePoint]
    public let records: [Record]
}


struct GlucoseWidgetEntryView : View {
    var entry: BGEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

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
        guard let current = entry.points.last, entry.points.count > 1 else {
            return ""
        }
        let previous = entry.points[entry.points.count - 2]
        let trend = (current.value - previous.value) / (current.date > previous.date ? current.date - previous.date : previous.date - current.date) * 60
        return "\(trend % ".1lf")"
    }
    
    private var levelFont: Font {
        switch family {
        case .systemSmall:
            return Font.system(.headline)
        case .systemMedium:
            return Font.system(size: 25, weight: .bold, design: Font.Design.default)
        case .systemLarge:
            return Font.system(size: 36, weight: .black, design: Font.Design.default)
        @unknown default:
            return Font.system(.headline)
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
                    .font(Font.monospacedDigit(Font.system(.caption))())
                    .minimumScaleFactor(0.5)
               
                switch (iob > 0, family) {
                case (true, .systemSmall):
                    Text("\(iob % ".1lf")")
                        .lineLimit(1)
                        .font(Font.monospacedDigit(Font.system(.caption2))())
                        .multilineTextAlignment(.center)
                        .layoutPriority(2)
                        .minimumScaleFactor(0.75)
                case (true, .systemMedium):
                    Text("\(iob % ".1lf")")
                        .lineLimit(1)
                        .font(Font.monospacedDigit(Font.system(.caption2))())
                        .layoutPriority(2)
                        .minimumScaleFactor(0.75)
                case (true, .systemLarge):
                    Text("BOB\n\(iob % ".1lf")")
                        .lineLimit(2)
                        .font(Font.monospacedDigit(Font.system(.caption))())
                        .multilineTextAlignment(.center)
                        .layoutPriority(2)
                        .minimumScaleFactor(0.75)
                case (false, .systemLarge):
                    Text("\n")
                        .lineLimit(2)
                        .font(Font.monospacedDigit(Font.system(.caption))())
                default:
                    EmptyView()
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
            
            BGWidgetGraph(points: entry.points, records: family == .systemLarge ? entry.records : [], hours: family == .systemSmall ? 2 : 4)
                .frame( maxWidth: .infinity,  maxHeight: .infinity)
        }
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
