//
//  BGWidget.swift
//  BGWidget
//
//  Created by Guy on 11/07/2020.
//  Copyright © 2020 TivStudio. All rights reserved.
//

import WidgetKit
import SwiftUI
import Intents
import WoofKit
import Sqlable

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
    
    public func snapshot(for configuration: ConfigurationIntent, with context: Context, completion: @escaping (BGEntry) -> ()) {
        readData { (points, records) in
            let entryDate = points.last?.date ?? Date()
            let entry = BGEntry(date: entryDate, configuration: configuration, points: points, records: records)
            completion(entry)
        }
    }

    public func timeline(for configuration: ConfigurationIntent, with context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        readData { (points, records) in
            let entryDate = points.last?.date ?? Date()
            let timeline = Timeline(entries: [BGEntry(date: entryDate, configuration: configuration, points: points, records: records)], policy: .after(entryDate + 3.m))
            completion(timeline)
        }
    }
    
    private func readData(completion: @escaping ([GlucosePoint], [Record]) -> Void) {
        DispatchQueue.global().async {
            self.coordinator.coordinate(readingItemAt: sharedDbUrl, error: nil, byAccessor: { (_) in
                if let p = self.sharedDb?.evaluate(GlucosePoint.read()) {
                    Storage.default.reloadToday()
                    let records = Storage.default.lastDay.entries
                    completion(p.sorted(by: { $0.date > $1.date }), records)
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

struct PlaceholderView : View {
    var body: some View {
        Text("Placeholder View")
    }
}

struct BGWidgetEntryView : View {
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
            return Font.system(size: 21, weight: .bold, design: Font.Design.default)
        case .systemLarge:
            return Font.system(size: 25, weight: .black, design: Font.Design.default)
        @unknown default:
            return Font.system(.headline)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(entry.date, style: .timer)
                    .font(Font.monospacedDigit(Font.system(.body))())
                Spacer()
                Text(trend)
                    .font(Font.system(.caption))
                Text(levelString)
                    .font(levelFont)
            }
            .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))

            BGWidgetGraph(points: entry.points)
                .frame( maxWidth: .infinity,  maxHeight: .infinity)
        }.background(colorScheme == .light ? Color(named: .lightGray) : Color(named: .darkGray))
    }
}

extension Color {
    init(named: UIColor) {
        self.init(named)
    }
}

@main
struct BGWidget: Widget {
    private let kind: String = "BGWidget"

    public var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: Provider(), placeholder: PlaceholderView()) { entry in
            BGWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("BG Widget")
        .description("Blood glucose widget.")
    }
}

struct BGWidget_Previews: PreviewProvider {
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
        BGWidgetEntryView(entry: BGEntry(date: Date() - 46.s, configuration: ConfigurationIntent(), points: BGWidget_Previews.points, records: []))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            BGWidgetEntryView(entry: BGEntry(date: Date() - 46.s, configuration: ConfigurationIntent(), points: BGWidget_Previews.points, records: []))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            
            BGWidgetEntryView(entry: BGEntry(date: Date() - 46.s, configuration: ConfigurationIntent(), points: BGWidget_Previews.points, records: []))
                .previewContext(WidgetPreviewContext(family: .systemLarge))

            BGWidgetEntryView(entry: BGEntry(date: Date() - 46.s, configuration: ConfigurationIntent(), points: BGWidget_Previews.points, records: []))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .environment(\.colorScheme, .dark)
        }
    }
}
