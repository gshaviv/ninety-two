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

struct StateData {
    private(set) var trendValue: Double
    private(set) var trendSymbol: String
    private(set) var readings:  [GlucosePoint]
    private(set) var iob: Double
    private(set) var insulinAction: Double
    private(set) var sensorAge: TimeInterval
    private(set) var batteryLevel: Int
}

enum Status {
    case ready
    case sending
    case error
    case snapshot
}

class AppState: ObservableObject {
    @Published var state: Status = .error
    var data: StateData = StateData(trendValue: 0, trendSymbol: "", readings: [], iob: 0, insulinAction: 0, sensorAge: 0, batteryLevel: 0) {
        didSet {
            self.state = .ready
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
        refresh()
    }
    
    func reconnectCmd() {
        appState.state = .sending
        WCSession.default.sendMessage(["op":["reconnect"]], replyHandler: { (_) in
            appState.state = .ready
        }) { (_) in
            appState.state = .ready
        }
    }

    func refresh(force: Bool = false, summary sendSummary: Bool = false) {
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
        var ops = ["state"]
        if defaults[.needsUpdateDefaults] {
            ops.insert("defaults", at: 0)
        }
        if (summary.data.period == 0 && defaults[.needUpdateSummary]) || sendSummary {
            ops.insert("summary", at: 0)
            defaults[.needUpdateSummary] = false
        }
        WCSession.default.sendMessage(["op":ops], replyHandler: { (info) in
            WCSession.replyHandler(info)
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

extension WCSession {
    static public func replyHandler(_ info: [String:Any]) {
        DispatchQueue.global().async {
            self.processSummary(from: info)
            self.processDefaults(from: info)
            guard let m = info["v"] as? [[Double]] else {
                return
            }
            let t = info["t"] as? Double ?? appState.data.trendValue
            let s = info["s"] as? String ?? appState.data.trendSymbol
            let iob = info["iob"] as? Double ?? appState.data.iob
            let act = info["ia"] as? Double ?? appState.data.insulinAction
            let age = info["age"] as? TimeInterval ?? appState.data.sensorAge
            let level = info["b"] as? Int ?? appState.data.batteryLevel
            let readings = m.compactMap { value -> GlucosePoint? in
                guard let d = value.first, let v = value.last else {
                    return nil
                }
                return GlucosePoint(date: Date(timeIntervalSince1970: d), value: v)
            }
           
            DispatchQueue.main.async {
                appState.data = StateData(trendValue: t, trendSymbol: s, readings: readings, iob: iob, insulinAction: act, sensorAge: age, batteryLevel: level)
                if let symbol = info["c"] as? String, let last = readings.last?.date, symbol != WKExtension.extensionDelegate.complicationState.string {
                    WKExtension.extensionDelegate.complicationState = DisplayValue(date: last, string: symbol)
                }
            }
        }
    }
    
    fileprivate static func processDefaults(from message: [String:Any]) {
        if let dflt = message["defaults"] as? [String: Any] {
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
        defaults[.needsUpdateDefaults] = false
    }
    
    fileprivate static func processSummary(from message: [String:Any]) {
        if let sumStr = message["summary"] as? String, let data = sumStr.data(using: .utf8) {
            do {
                let sumData = try JSONDecoder().decode(Summary.self, from: data)
                DispatchQueue.main.async {
                    summary.data = sumData
                    defaults[.needUpdateSummary] = false
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
        if let d = userInfo["d"] as? Double, let v = userInfo["v"] as? String {
            complicationState = DisplayValue(date: Date(timeIntervalSince1970: d), string: v)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        WCSession.replyHandler(applicationContext)
    }
    

    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        WCSession.processDefaults(from: message)
        WCSession.processSummary(from: message)
        replyHandler(["ok": true])
    }
    
}

extension WKExtension {
    static var extensionDelegate: ExtensionDelegate {
        return shared().delegate as! ExtensionDelegate
    }
}
