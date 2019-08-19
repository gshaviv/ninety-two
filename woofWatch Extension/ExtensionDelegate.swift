//
//  ExtensionDelegate.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import WatchKit
import WatchConnectivity

extension WKExtension {
    static public let willEnterForegroundNotification = Notification.Name("willEnterForeground")
    static public let didEnterBackgroundNotification = Notification.Name("didEnterBackground")
}

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    private(set) public var data = DisplayValue(date: Date(), string: "-")
    private(set) public var trendValue: Double = 0
    private(set) public var trendSymbol: String = ""
    private(set) public var readings =  [GlucosePoint]()
    private(set) public var iob: Double = 0
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
        refresh(blank: .little)
    }

    private var isSending = false
    func refresh(blank: InterfaceController.DimState = .none) {
        guard Date() - lastRefreshDate > 20.s && !isSending else {
            return
        }
        if let last = readings.last {
            if last.value >= 70 && Date() - last.date < 3.m {
                return
            } else if last.value < 70 && Date() - last.date < 1.m {
                return
            }
        }
        
        isSending = true
        if let ctr = WKExtension.shared().rootInterfaceController as? InterfaceController {
            ctr.isDimmed = InterfaceController.DimState(rawValue: max(blank.rawValue, ctr.isDimmed.rawValue))!
        }
        WCSession.default.sendMessage(["op":"state"], replyHandler: { (info) in
            self.isSending = false
            guard let t = info["t"] as? Double, let s = info["s"] as? String, let m = info["v"] as? [Any], let iob = info["iob"] as? Double else {
                return
            }
            DispatchQueue.main.async {
                log("iob=\(iob)")
                self.iob = iob
                self.lastRefreshDate = Date()
                self.trendValue = t
                self.trendSymbol = s
                self.readings = m.compactMap {
                    guard let a = $0 as? [Any], let d = a.first as? Date, let v = a.last as? Double else {
                        return nil
                    }
                    return GlucosePoint(date: d, value: v)
                }
                if let controller = WKExtension.shared().rootInterfaceController as? InterfaceController {
                    DispatchQueue.main.async {
                        controller.update()
                    }
                }
                if let symbol = info["c"] as? String, let last = self.readings.last?.date, symbol != self.data.string {
                    self.data = DisplayValue(date: last, string: symbol)
                    self.reloadComplication()
                }
            }
        }) { (_) in
            self.isSending = false
            if let controller = WKExtension.shared().rootInterfaceController as? InterfaceController {
                DispatchQueue.main.async {
                    controller.showError()
                }
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
                if let ctr = WKExtension.shared().rootInterfaceController as? InterfaceController {
                    ctr.isDimmed = .dim
                }
                
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
            data = DisplayValue(date: Date(timeIntervalSince1970: d), string: v)
            reloadComplication()
            self.isSending = false
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let t = applicationContext["t"] as? Double, let s = applicationContext["s"] as? String, let m = applicationContext["v"] as? [Any] else {
            return
        }
        trendValue = t
        trendSymbol = s
        isSending = false
        readings = m.compactMap {
            guard let a = $0 as? [Any], let d = a.first as? Date, let v = a.last as? Double else {
                return nil
            }
            return GlucosePoint(date: d, value: v)
        }
        if let controller = WKExtension.shared().rootInterfaceController as? InterfaceController {
            DispatchQueue.main.async {
                controller.update()
            }
        }
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
        replyHandler(["ok": true])
    }
    
}

extension WKExtension {
    static var extensionDelegate: ExtensionDelegate {
        return shared().delegate as! ExtensionDelegate
    }
}
