//
//  ExtensionDelegate.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import WatchKit
import WatchConnectivity

//#if targetEnvironment(simulator)
//let refreshInterval = 30.s
//#else
//let refreshInterval: TimeInterval = {
//    if let last = WKExtension.extensionDelegate.data.last, last.value < 70 {
//        return 1.m
//    }
//    return 5.m
//}()
//#endif

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    public private(set) var data = DisplayValue(date: Date(), string: "-")


    func applicationDidFinishLaunching() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func applicationDidBecomeActive() {

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
//                WCSession.default.sendMessage(["op": "refresh"], replyHandler: nil) { (err) in
//                    print("\(err)")
//                }
//                WCSession.default.sendMessage(["op": "refresh"], replyHandler: { (response) in
//                    if let got = response["d"] as? [[String:Any]] {
//                        for info in got {
//                            self.session(WCSession.default, didReceiveUserInfo: info)
//                        }
//                        self.reloadComplication()
//                    }
//                    if let last = self.data.last?.date {
//                        WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: last + refreshInterval, userInfo: nil) { (err) in
//
//                        }
//                    }
//                }) { (_) in
//                    self.pendingTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
//                    self.pendingTasks = []
//                }
//                WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: Date() + refreshInterval, userInfo: nil) { (err) in
//
//                }
                backgroundTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
//                if WCSession.default.hasContentPending {
//                    pendingTasks.insert(connectivityTask)
//                } else {
//                    WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: Date() + refreshInterval, userInfo: nil) { (err) in
//
//                    }
                    connectivityTask.setTaskCompletedWithSnapshot(false)
//                }
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

    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if  let d = userInfo["d"] as? Double, let v = userInfo["v"] as? String {
            data = DisplayValue(date: Date(timeIntervalSince1970: d), string: v)
            reloadComplication()
//            if !session.hasContentPending {
//                WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: Date() + refreshInterval, userInfo: nil) { (err) in
//
//                }
//                pendingTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
//                pendingTasks = []
//            }
        }
    }

//    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
//        if let got = message["d"] as? [[String:Any]] {
//            for userInfo in got {
//                if let d = userInfo["d"] as? Double, let v = userInfo["v"] as? Double, let sym = userInfo["t"] as? String {
//                    let val = DisplayValue(date: Date(timeIntervalSince1970: d), value: v, trendSymbol: sym)
//                    insert(data: val)
//                }
//            }
//            self.reloadComplication()
//        }
//        if let last = self.data.last?.date {
//            WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: last + refreshInterval, userInfo: nil) { (err) in
//
//            }
//        }
//
//    }

}


extension WKExtension {
    static var extensionDelegate: ExtensionDelegate {
        return shared().delegate as! ExtensionDelegate
    }
}
