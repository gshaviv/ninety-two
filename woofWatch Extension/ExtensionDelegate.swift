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

struct State {
    private(set) var trendValue: Double
    private(set) var trendSymbol: String
    private(set) var readings:  [GlucosePoint]
    private(set) var iob: Double
    private(set) var insulinAction: Double
}

enum Status {
    case ready
    case sending
    case error
}

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    private(set) var complicationState = DisplayValue(date: Date(), string: "-")
    private(set) var data = State(trendValue: 0, trendSymbol: "", readings: [], iob: 0, insulinAction: 0) {
        didSet {
            self.appState = .ready
        }
    }
    @Published private var appState: Status = .error
    private(set) lazy var state = $appState.map { ($0, self.data) }.eraseToAnyPublisher()
    

    private var lastRefreshDate = Date.distantPast
    
    override init() {
        defaults.register()
    }

    func applicationDidFinishLaunching() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func applicationWillEnterForeground() {
        refresh(blank: .dim)
        NotificationCenter.default.post(name: WKExtension.willEnterForegroundNotification, object: nil)
    }

    func applicationDidEnterBackground() {
        NotificationCenter.default.post(name: WKExtension.didEnterBackgroundNotification, object: nil)
    }
    
    func applicationDidBecomeActive() {
        appState = .ready
        refresh(blank: .little)
    }

    func refresh(blank: InterfaceController.DimState = .none) {
        guard Date() - lastRefreshDate > 20.s && appState != .sending else {
            return
        }
        if let last = data.readings.last {
            if last.value >= 70 && Date() - last.date < 3.m {
                return
            } else if last.value < 70 && Date() - last.date < 1.m {
                return
            }
        }
        
        appState = .sending
//        if let ctr = WKExtension.shared().rootInterfaceController as? InterfaceController {
//            ctr.isDimmed = InterfaceController.DimState(rawValue: max(blank.rawValue, ctr.isDimmed.rawValue))!
//        }
        var ops = ["state"]
        if defaults[.needsUpdateDefaults] {
            ops.insert("defaults", at: 0)
        }
        WCSession.default.sendMessage(["op":ops], replyHandler: { (info) in
            guard let t = info["t"] as? Double, let s = info["s"] as? String, let m = info["v"] as? [Any], let iob = info["iob"] as? Double , let act = info["ia"] as? Double else {
                return
            }
            let readings = m.compactMap { value -> GlucosePoint? in
                guard let a = value as? [Any], let d = a.first as? Date, let v = a.last as? Double else {
                    return nil
                }
                return GlucosePoint(date: d, value: v)
            }
            self.data = State(trendValue: t, trendSymbol: s, readings: readings, iob: iob, insulinAction: act)
                
            DispatchQueue.main.async {
                if let symbol = info["c"] as? String, let last = readings.last?.date, symbol != self.complicationState.string {
                    self.complicationState = DisplayValue(date: last, string: symbol)
                    self.reloadComplication()
                }
            }
        }) { (_) in
            self.appState = .error
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
//                if let ctr = WKExtension.shared().rootInterfaceController as? InterfaceController {
//                    ctr.isDimmed = .dim
//                }
                
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
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
                self.refresh(blank: .dim)
            }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let d = userInfo["d"] as? Double, let v = userInfo["v"] as? String {
            complicationState = DisplayValue(date: Date(timeIntervalSince1970: d), string: v)
            reloadComplication()
//            self.appState = .ready
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let t = applicationContext["t"] as? Double, let s = applicationContext["s"] as? String, let m = applicationContext["v"] as? [Any], let act = applicationContext["ia"] as? Double, let iob = applicationContext["iob"] as? Double else {
            return
        }
        let readings = m.compactMap { value -> GlucosePoint? in
            guard let a = value as? [Any], let d = a.first as? Date, let v = a.last as? Double else {
                return nil
            }
            return GlucosePoint(date: d, value: v)
        }
        self.data = State(trendValue: t, trendSymbol: s, readings: readings, iob: iob, insulinAction: act)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
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
        replyHandler(["ok": true])
    }
    
}

extension WKExtension {
    static var extensionDelegate: ExtensionDelegate {
        return shared().delegate as! ExtensionDelegate
    }
}
