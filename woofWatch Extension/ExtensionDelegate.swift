//
//  ExtensionDelegate.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import WatchKit
import WatchConnectivity
import Combine
import ClockKit


extension WKExtension {
    static public let willEnterForegroundNotification = Notification.Name("willEnterForeground")
    static public let didEnterBackgroundNotification = Notification.Name("didEnterBackground")
}

struct StateData: Equatable {    
    private(set) var trendValue: Double
    private(set) var trendSymbol: String
    var readings:  [GlucosePoint] {
        history + trend
    }
    private(set) var trend:[GlucosePoint]
    private(set) var history:[GlucosePoint]
    private(set) var events: [Event]
    var iob: Double {
        events.iob()
    }
    var sensorAge: TimeInterval {
        Date() - sensorBegin
    }
    private(set) var sensorBegin: Date
    private(set) var batteryLevel: Int
}

enum Status {
    case ready
    case sending
    case error
    case snapshot
}

class AppState: ObservableObject {
    @Published var state: Status = .error {
        didSet {
            if state != oldValue {
                lastStateChange = Date()
            }
        }
    }
    var lastStateChange = Date.distantPast
    var data: StateData = StateData(trendValue: 0, trendSymbol: "", trend: [], history: [], events: [],  sensorBegin: Date(), batteryLevel: -1) {
        didSet {
            self.state = .ready
            if oldValue != data {
                lastStateChange = Date()
            }
        }
    }
}

var appState = AppState()
var summary = SummaryInfo(Summary(period: 0, actualPeriod: 0, timeInRange: Summary.TimeInRange(low: 1, inRange: 1, high: 1), maxLevel: 180, minLevel: 70, average: 92, a1c: Summary.EA1C(value: 6.1, range: 0.1), low: Summary.Low(count: 0, median: 0), atdd: 0, timeInLevel: [1,1,1,1,1,1], daily: [], date: Date.distantPast))

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    fileprivate(set) var complicationState = DisplayValue(date: Date(), string: "-") {
        didSet {
            DispatchQueue.main.async {
                self.reloadComplication()
            }
        }
    }
    private var lastRefreshDate = Date.distantPast
    
    override init() {
        super.init()
        defaults.register()
    }

    func applicationDidFinishLaunching() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func applicationWillEnterForeground() {
        NotificationCenter.default.post(name: WKExtension.willEnterForegroundNotification, object: nil)
    }

    func applicationDidEnterBackground() {
        NotificationCenter.default.post(name: WKExtension.didEnterBackgroundNotification, object: nil)
    }
    
    func applicationDidBecomeActive() {
        if appState.state == .snapshot {
            appState.state = .ready
        }
        if appState.data.readings.isEmpty {
            refresh(force: true)
        } else {
            refresh()
        }
    }
    
    func reconnectCmd() {
        appState.state = .sending
        WCSession.default.sendMessage(["op":["reconnect"]], replyHandler: { (_) in
            appState.state = .ready
        }) { (_) in
            appState.state = .ready
        }
    }

    var lastFullState = Date.distantPast
    func refresh(force: Bool = false, summary sendSummary: Bool = false) {
        if appState.state == .sending && Date() - appState.lastStateChange > 20.s {
            appState.state = .ready
        }
        guard Date() - lastRefreshDate > 20.s && (appState.state != .sending || force || sendSummary) else {
            return
        }
        if let last = appState.data.readings.last {
            if last.value >= 70 && Date() - last.date < 3.m {
                return
            } else if last.value < 70 && Date() - last.date < 1.m {
                return
            }
        }
        appState.state = .sending
        let cmd: String
        if appState.data.batteryLevel <= 0 || appState.data.readings.isEmpty || Date() - lastFullState > 4.h {
            lastFullState = Date()
            cmd = "fullState"
        } else {
            cmd = "state"
        }
        var ops = [cmd]
        if defaults[.level0] == 0 {
            ops.insert("defaults", at: 0)
        }
        if summary.data.period == 0 || sendSummary {
            ops.insert("summary", at: 0)
        }
        WCSession.default.sendMessage(["op":ops], replyHandler: { (info) in
            ExtensionDelegate.replyHandler(info)
        }) { (_) in
            DispatchQueue.main.async {
                appState.state = .error
            }
        }
    }

    //    var pendingTasks = Set<WKRefreshBackgroundTask>()
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // Sent when the system needs to launch the application in the background to process tasks. Tasks arrive in a set, so loop through and process each one.
        for task in backgroundTasks {
            // Use a switch statement to check the task type
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                 backgroundTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                appState.state = .snapshot
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date() + 1.h, userInfo: nil)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                connectivityTask.setTaskCompletedWithSnapshot(false)
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                urlSessionTask.setTaskCompletedWithSnapshot(false)
            case let relevantShortcutTask as WKRelevantShortcutRefreshBackgroundTask:
                relevantShortcutTask.setTaskCompletedWithSnapshot(false)
            case let intentDidRunTask as WKIntentDidRunRefreshBackgroundTask:
                intentDidRunTask.setTaskCompletedWithSnapshot(false)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    func reloadComplication() {
        let complicationServer = CLKComplicationServer.sharedInstance()
        guard let cmpls = complicationServer.activeComplications else {
            return
        }
        for complication in cmpls {
            complicationServer.reloadTimeline(for: complication)
        }
    }
}

extension ExtensionDelegate {
    static public func replyHandler(_ info_in: [String:Any]) {
        DispatchQueue.global().async {
            let info = info_in.withStateKeys()
            _ = self.processSummary(from: info)
            _ = self.processDefaults(from: info)
            if let symbol = info[.complication] as? String,  symbol != WKExtension.extensionDelegate.complicationState.string {
                DispatchQueue.main.async {
                    WKExtension.extensionDelegate.complicationState = DisplayValue(date: Date(), string: symbol)
                }
            }
            guard let m = info[.trend] as? [[Double]] else {
                DispatchQueue.main.async {
                    appState.state = .ready
                }
                return
            }
            let t = info[.change] as? Double ?? appState.data.trendValue
            let s = trendSymbol(for: t)
            let events = (info[.events] as? [[Double]])?.map { Event(date: $0[0], bolus: $0[1]) } ?? appState.data.events
            let begin = info[.sensorStart] as? Date ?? appState.data.sensorBegin
            let level = info[.batteryLevel] as? Int ?? appState.data.batteryLevel
            let trend = m.compactMap { value -> GlucosePoint? in
                guard let d = value.first, let v = value.last else {
                    return nil
                }
                return GlucosePoint(date: Date(timeIntervalSince1970: d), value: v, isTrend: true)
            }
            let newHistory: [GlucosePoint]
            if let m = info[.history] as? [[Double]] {
                newHistory = m.compactMap { value -> GlucosePoint? in
                    guard let d = value.first, let v = value.last else {
                        return nil
                    }
                    return GlucosePoint(date: Date(timeIntervalSince1970: d), value: v)
                }
            } else {
                newHistory = []
            }
            let complateHistory: [GlucosePoint]
            if let first = newHistory.first {
                complateHistory = appState.data.history.filter { $0.date > Date() - 3.h - 16.m && $0.date < first.date } + newHistory
            } else {
                complateHistory = appState.data.history
            }
            if let lastHistory = complateHistory.last, let firstTrend = trend.first, lastHistory.date < firstTrend.date - 20.m {
                WKExtension.extensionDelegate.lastFullState = Date.distantPast
            }
            if let firstHistory = complateHistory.first, firstHistory.date > Date() - 2.h {
                WKExtension.extensionDelegate.lastFullState = Date.distantPast
            }
            DispatchQueue.main.async {
                appState.data = StateData(trendValue: t, trendSymbol: s, trend: trend, history: complateHistory, events: events,  sensorBegin: begin, batteryLevel: level)
            }
        }
    }
    
    fileprivate static func processDefaults(from message: [StateKey:Any]) -> Bool {
        if let dflt = message[.defaults] as? [String: Any] {
            dflt.forEach {
                log("Got default: \($0.key) = \($0.value)")
                switch $0.value {
                case let v as Double:
                    defaults.set(v, forKey: $0.key)
                    
                case let v as String:
                    defaults.set(v, forKey: $0.key)
                    
                case let v as Bool:
                    defaults.set(v, forKey: $0.key)
                    
                default:
                    return
                }
            }
            return true
        }
        return false
    }
    
    fileprivate static func processSummary(from message: [StateKey:Any]) -> Bool {
        if let sumStr = message[.summary] as? String, let data = sumStr.data(using: .utf8) {
            do {
                let sumData = try JSONDecoder().decode(Summary.self, from: data)
                DispatchQueue.main.async {
                    summary.data = sumData
                }
                return true
            } catch {
            }
        }
        return false
    }
}

extension ExtensionDelegate: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if session.activationState == .activated {
            DispatchQueue.main.async {
                self.refresh(force: true)
            }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if  let v = userInfo.withStateKeys()[.complication] as? String {
            DispatchQueue.main.async {
                self.complicationState = DisplayValue(date: Date(), string: v)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        ExtensionDelegate.replyHandler(applicationContext)
    }
    

    
    func session(_ session: WCSession, didReceiveMessage info: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        ExtensionDelegate.replyHandler(info)
        replyHandler(["ok": true])
    }
    
}

extension WKExtension {
    static var extensionDelegate: ExtensionDelegate {
        return shared().delegate as! ExtensionDelegate
    }
}
