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
var summary = SummaryInfo(Summary(period: 0, timeInRange: Summary.TimeInRange(low: 1, inRange: 1, high: 1), maxLevel: 180, minLevel: 70, average: 92, a1c: 6.0, low: Summary.Low(count: 0, median: 0), atdd: 0, timeInLevel: [1,1,1,1,1,1]))

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    private(set) var complicationState = DisplayValue(date: Date(), string: "-") {
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
        refresh()
        NotificationCenter.default.post(name: WKExtension.willEnterForegroundNotification, object: nil)
    }

    func applicationDidEnterBackground() {
        NotificationCenter.default.post(name: WKExtension.didEnterBackgroundNotification, object: nil)
    }
    
    func applicationDidBecomeActive() {
        if appState.state == .snapshot {
            appState.state = .ready
        }
        refresh(force: true)
    }

    func refresh(force: Bool = false) {
        guard Date() - lastRefreshDate > 20.s && (appState.state != .sending || force) else {
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
//        if let ctr = WKExtension.shared().rootInterfaceController as? InterfaceController {
//            ctr.isDimmed = InterfaceController.DimState(rawValue: max(blank.rawValue, ctr.isDimmed.rawValue))!
//        }
        var ops = ["state"]
        if defaults[.needsUpdateDefaults] {
            ops.insert("defaults", at: 0)
        }
        if summary.data.period == 0 && defaults[.needUpdateSummary] {
            ops.insert("summary", at: 0)
            defaults[.needUpdateSummary] = false
        }
        WCSession.default.sendMessage(["op":ops], replyHandler: { (info) in
            guard let t = info["t"] as? Double, let s = info["s"] as? String, let m = info["v"] as? [Any], let iob = info["iob"] as? Double , let act = info["ia"] as? Double, let age = info["age"] as? TimeInterval, let level = info["b"] as? Int else {
                return
            }
            DispatchQueue.global().async {
                let readings = m.compactMap { value -> GlucosePoint? in
                    guard let a = value as? [Any], let d = a.first as? Date, let v = a.last as? Double else {
                        return nil
                    }
                    return GlucosePoint(date: d, value: v)
                }
                self.processDefaults(from: info)
                self.processSummary(from: info)
                
                DispatchQueue.main.async {
                    appState.data = StateData(trendValue: t, trendSymbol: s, readings: readings, iob: iob, insulinAction: act, sensorAge: age, batteryLevel: level)
                    if let symbol = info["c"] as? String, let last = readings.last?.date, symbol != self.complicationState.string {
                        self.complicationState = DisplayValue(date: last, string: symbol)
                    }
                }
            }
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
        guard let t = applicationContext["t"] as? Double, let s = applicationContext["s"] as? String, let m = applicationContext["v"] as? [Any], let act = applicationContext["ia"] as? Double, let iob = applicationContext["iob"] as? Double, let age = applicationContext["age"] as? TimeInterval, let level = applicationContext["b"] as? Int else {
            return
        }
        DispatchQueue.global().async {
            let readings = m.compactMap { value -> GlucosePoint? in
                guard let a = value as? [Any], let d = a.first as? Date, let v = a.last as? Double else {
                    return nil
                }
                return GlucosePoint(date: d, value: v)
            }
            DispatchQueue.main.async {
                appState.data = StateData(trendValue: t, trendSymbol: s, readings: readings, iob: iob, insulinAction: act, sensorAge: age, batteryLevel: level)
            }
        }
    }
    
    private func processDefaults(from message: [String:Any]) {
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
    
    private func processSummary(from message: [String:Any]) {
        if let sumStr = message["summary"] as? String, let data = sumStr.data(using: .utf8) {
            do {
                let sumData = try JSONDecoder().decode(Summary.self, from: data)
                DispatchQueue.main.async {
                    summary.data = sumData
                }
            } catch {}
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        processDefaults(from: message)
        processSummary(from: message)
        replyHandler(["ok": true])
    }
    
}

extension WKExtension {
    static var extensionDelegate: ExtensionDelegate {
        return shared().delegate as! ExtensionDelegate
    }
}
