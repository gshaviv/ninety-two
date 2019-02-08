//
//  ExtensionDelegate.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import WatchKit
import WatchConnectivity


class ExtensionDelegate: NSObject, WKExtensionDelegate {
    private(set) public var data = DisplayValue(date: Date(), string: "-")
    private(set) public var trendValue: Double = 0
    private(set) public var trendSymbol: String = ""
    private(set) public var readings =  [GlucosePoint]()
    private(set) public var iob: Double = 0
    private var lastRefreshDate = Date.distantPast

    func applicationDidFinishLaunching() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func applicationWillEnterForeground() {
        if let ctr = WKExtension.shared().rootInterfaceController as? InterfaceController {
            if !readings.isEmpty {
                ctr.updateTime()
            }
            refresh(blank: true)
        }
    }


    func refresh(blank: Bool = false) {
        guard Date() - lastRefreshDate > 15.s else {
            return
        }
        if blank, let ctr = WKExtension.shared().rootInterfaceController as? InterfaceController {
            ctr.setDim()
        }
        WCSession.default.sendMessage(["op":"state"], replyHandler: { (info) in
            guard let t = info["t"] as? Double, let s = info["s"] as? String, let m = info["v"] as? [Any], let iob = info["iob"] as? Double else {
                return
            }
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
        }) { (_) in
            if let controller = WKExtension.shared().rootInterfaceController as? InterfaceController {
                DispatchQueue.main.async {
                    controller.showError()
                }
            }
        }
    }

    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
        //        WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: Date() + refreshInterval, userInfo: nil) { (err) in
        //
        //        }
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
                    ctr.setDim()
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
        if session.activationState == .activated, let ctr = WKExtension.shared().rootInterfaceController as? InterfaceController {
            ctr.updateTime()
            refresh(blank: true)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let d = userInfo["d"] as? Double, let v = userInfo["v"] as? String {
            data = DisplayValue(date: Date(timeIntervalSince1970: d), string: v)
            reloadComplication()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let t = applicationContext["t"] as? Double, let s = applicationContext["s"] as? String, let m = applicationContext["v"] as? [Any] else {
            return
        }
        trendValue = t
        trendSymbol = s
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
}

extension WKExtension {
    static var extensionDelegate: ExtensionDelegate {
        return shared().delegate as! ExtensionDelegate
    }
}
