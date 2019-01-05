//
//  ComplicationController.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import ClockKit
import WatchKit

class ComplicationController: NSObject, CLKComplicationDataSource {
    
    // MARK: - Timeline Configuration
    
    func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([])
    }
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.hideOnLockScreen)
    }
    
    // MARK: - Timeline Population
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // Call the handler with the current timeline entry
        let current = WKExtension.extensionDelegate.data

        if let template = getTemplates(family: complication.family, data: current) {
            let entry = CLKComplicationTimelineEntry(date: current.date, complicationTemplate: template)
            handler(entry)
        } else {
            handler(nil)
        }
    }
    
    func getTimelineEntries(for complication: CLKComplication, before date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // Call the handler with the timeline entries prior to the given date
//        if let start = WKExtension.extensionDelegate.data.lastIndex(where: { $0.date < date }) {
//            var entries = [CLKComplicationTimelineEntry]()
//            for idx in max(start - limit, 0) ..< start {
//                let current = WKExtension.extensionDelegate.data[idx]
//                if let template = getTemplates(family: complication.family, data: current) {
//                    let entry = CLKComplicationTimelineEntry(date: current.date, complicationTemplate: template)
//                    entries.append(entry)
//                }
//            }
//            handler(entries)
//            return
//        }
        handler(nil)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // Call the handler with the timeline entries after to the given date
        handler(nil)
    }
    
    // MARK: - Placeholder Templates
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        // This method will be called once per supported complication, and the results will be cached
        if let template = getTemplates(family: complication.family, data: DisplayValue(date: Date(), string: "OK")) {
            handler(template)
        } else {
            handler(nil)
        }
    }


    private func getTemplates(family: CLKComplicationFamily, data current: DisplayValue) -> CLKComplicationTemplate? {
        switch family {
        case .circularSmall:
            let t = CLKComplicationTemplateCircularSmallSimpleText()
            t.textProvider = CLKSimpleTextProvider(text: current.string)
            return t

        case .modularSmall:
            let t = CLKComplicationTemplateModularSmallSimpleText()
            t.textProvider = CLKSimpleTextProvider(text: current.string)
            return t

        case .utilitarianSmall:
            let t = CLKComplicationTemplateUtilitarianSmallFlat()
            t.textProvider = CLKSimpleTextProvider(text: current.string)
            return t

        default:
            return nil
        }
    }
}
