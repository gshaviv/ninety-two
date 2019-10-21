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


extension WKExtension {
    static public let willEnterForegroundNotification = Notification.Name("willEnterForeground")
    static public let didEnterBackgroundNotification = Notification.Name("didEnterBackground")
}

struct StateData: Equatable {    
    private(set) var trendValue: Double
    private(set) var trendSymbol: String
    private(set) var readings:  [GlucosePoint]
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
    var data: StateData = StateData(trendValue: 0, trendSymbol: "", readings: [], events: [],  sensorBegin: Date(), batteryLevel: -1) {
        didSet {
            self.state = .ready
            if oldValue != data {
                lastStateChange = Date()
            }
        }
    }
}

var appState = AppState()
var summary = SummaryInfo(Summary(period: 0, timeInRange: Summary.TimeInRange(low: 1, inRange: 1, high: 1), maxLevel: 180, minLevel: 70, average: 92, a1c: Summary.EA1C(value: 6.1, range: 0.1), low: Summary.Low(count: 0, median: 0), atdd: 0, timeInLevel: [1,1,1,1,1,1]))

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
            appState.state = .error
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
    private static func trendSymbol(for trend: Double) -> String {
         if trend > 2.0 {
            return "⇈"
        } else if trend > 1.0 {
            return "↑"
        } else if trend > 0.33 {
            return "↗︎"
        } else if trend > -0.33 {
            return "→"
        } else if trend > -1.0 {
            return "↘︎"
        } else if trend > -2.0 {
            return "↓"
        } else {
            return "⇊"
        }
    }
    static public func replyHandler(_ info_in: [String:Any]) {
        DispatchQueue.global().async {
            let info = info_in.withStateKeys()
            self.processSummary(from: info)
            self.processDefaults(from: info)
            guard let m = info[.measurements] as? [[Double]] else {
                DispatchQueue.main.async {
                    appState.state = .ready
                }
                return
            }
            let t = info[.trendValue] as? Double ?? appState.data.trendValue
            let s = trendSymbol(for: t)
            let events = (info[.events] as? [[Double]])?.map { Event(date: $0[0], bolus: $0[1]) } ?? appState.data.events
            let begin = info[.sensorStart] as? Date ?? appState.data.sensorBegin
            let level = info[.battery] as? Int ?? appState.data.batteryLevel
            let newReadings = m.compactMap { value -> GlucosePoint? in
                guard let d = value.first, let v = value.last else {
                    return nil
                }
                return GlucosePoint(date: Date(timeIntervalSince1970: d), value: v)
            }
            let readings: [GlucosePoint]
            if let first = newReadings.first {
                readings = appState.data.readings.filter { $0.date > Date() - 3.h - 16.m && $0.date < first.date } + newReadings
            } else {
                readings = appState.data.readings
            }
            DispatchQueue.main.async {
                appState.data = StateData(trendValue: t, trendSymbol: s, readings: readings, events: events,  sensorBegin: begin, batteryLevel: level)
                if let symbol = info[.complication] as? String,  symbol != WKExtension.extensionDelegate.complicationState.string {
                    WKExtension.extensionDelegate.complicationState = DisplayValue(date: Date(), string: symbol)
                }
            }
        }
    }
    
    fileprivate static func processDefaults(from message: [StateKey:Any]) {
        if let dflt = message[.defaults] as? [String: Any] {
            dflt.forEach {
                switch $0.value {
                case let v as Double:
                    defaults.set(v, forKey: $0.key)
                    
                case let v as String:
                    defaults.set(v, forKey: $0.key)
                    
                default:
                    return
                }
            }
        }
    }
    
    fileprivate static func processSummary(from message: [StateKey:Any]) {
        if let sumStr = message[.summary] as? String, let data = sumStr.data(using: .utf8) {
            do {
                let sumData = try JSONDecoder().decode(Summary.self, from: data)
                DispatchQueue.main.async {
                    summary.data = sumData
                }
            } catch {}
        }
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
        let message = info.withStateKeys()
        ExtensionDelegate.processDefaults(from: message)
        ExtensionDelegate.processSummary(from: message)
        replyHandler(["ok": true])
    }
    
}

extension WKExtension {
    static var extensionDelegate: ExtensionDelegate {
        return shared().delegate as! ExtensionDelegate
    }
}
