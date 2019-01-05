//
//  AppDelegate.swift
//  WoofWoof
//
//  Created by Guy on 14/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import UIKit
import UserNotifications
import WatchConnectivity

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    #if targetEnvironment(simulator)
    var updater: Repeater?
    #endif
    private(set) public var trendCalculator: Calculation<Double?>!
    private var watchState: String = ""

    override init() {
        super.init()
        defaults[.lastStatisticsCalculation] = nil
        trendCalculator = Calculation {
            return self.trendValue()
        }
        defaults.register()
    }


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        Central.manager.onStateChange { (before, now) in
            log("State changed from \(before) to \(now)")
        }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert], completionHandler: { granted, _ in
            log("Notifications granted=\(granted)")
        })

        WCSession.default.delegate = self
        WCSession.default.activate()

        MiaoMiao.addDelegate(self)

        #if targetEnvironment(simulator)
        var lastHistoryDate = Date() - 20.m
        MiaoMiao.last24hReadings.append(GlucosePoint(date: lastHistoryDate, value: 70 + Double(arc4random_uniform(40))))
        updater = Repeater.every(60, perform: { (_) in
            let newValue = 70 + Double(arc4random_uniform(40))
            let gp = GlucosePoint(date: Date(), value: newValue)
            MiaoMiao.trend = [gp,
            GlucosePoint(date: Date() - 1.m, value: newValue + Double(arc4random_uniform(100))/50 - 1),
            GlucosePoint(date: Date() - 2.m, value: newValue + Double(arc4random_uniform(100))/50 - 1),
            GlucosePoint(date: Date() - 3.m, value: newValue + Double(arc4random_uniform(100))/50 - 1),
            GlucosePoint(date: Date() - 4.m, value: newValue + Double(arc4random_uniform(100))/50 - 1)]
            
            MiaoMiao.delegate?.forEach { $0.didUpdateGlucose() }
            if Date() - lastHistoryDate > 5.m {
                MiaoMiao.last24hReadings.append(gp)
                MiaoMiao.delegate?.forEach { $0.didUpdate(addedHistory: [gp]) }
                lastHistoryDate = Date()
            }
        })
        #endif

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


    private func trendValue() -> Double? {
        guard let trend = MiaoMiao.trend else {
            return nil
        }
        let diffs = trend.map { $0.value }.diff()
        if diffs.count > 4 {
            let ave = diffs[0 ..< 4].reversed().reduce(0) { $1 == 0 ? $0 : ($1 + $0) / 2 }
            return -ave
        }
        return nil
    }

    func trendSymbol(for inputTrend: Double? = nil) -> String {
        guard let trend = inputTrend ?? trendCalculator.value else {
            return ""
        }
        if trend > 2.8 {
            return "⇈"
        } else if trend > 1.4 {
            return "↑"
        } else if trend > 0.7 {
            return "↗︎"
        } else if trend > -0.7 {
            return "→"
        } else if trend > -1.4 {
            return "↘︎"
        } else if trend > -2.8 {
            return "↓"
        } else {
            return "⇊"
        }
    }

}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.badge, .sound, .alert])
    }
}

extension AppDelegate: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {

    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        if WCSession.default.isComplicationEnabled, let current = MiaoMiao.trend?.first {
            WCSession.default.transferUserInfo(["d": current.date.timeIntervalSince1970, "v": current.value, "c":true])
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {

    }

//    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
//        guard let  op = message["op"] as? String else {
//            replyHandler([:])
//            return
//        }
//        switch op {
//        case "refresh":
//            replyHandler(["d": pendingWatchPoints])
//            pendingWatchPoints = []
//
//        default:
//            replyHandler([:])
//        }
//    }

//    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
//        guard let  op = message["op"] as? String else {
//            return
//        }
//        switch op {
//        case "refresh":
//            let pending = pendingWatchPoints
//            pendingWatchPoints = []
//            session.sendMessage(["d": pending], replyHandler: nil, errorHandler: { (err) in
//                logError("Error seding response: \(err.localizedDescription)")
//                self.pendingWatchPoints.append(contentsOf: pending)
//            })
//
//        default:
//            break
//        }
//    }


}


extension AppDelegate: MiaoMiaoDelegate {
    func showAlert(title: String?, body: String?, sound: UNNotificationSoundName?) {
        DispatchQueue.main.async {
            let notification = UNMutableNotificationContent()
            if let title = title {
                notification.title = title
            }
            if let body = body {
                notification.body = body
            }
            if let sound = sound {
                notification.sound = UNNotificationSound(named: sound)
            }
            notification.categoryIdentifier = "event"
            let request = UNNotificationRequest(identifier: "event", content: notification, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                if let err = err {
                    logError("\(err)")
                }
            })
        }
    }

    func didUpdateGlucose() {
        trendCalculator.invalidate()
        if let current = MiaoMiao.currentGlucose {
            if let trend = trendValue() {
                switch current.value {
                case ...defaults[.lowAlertLevel] where !defaults[.didAlertEvent] && trend < -0.25:
                    defaults[.didAlertEvent] = true
                    showAlert(title: "Low Glucose", body: nil, sound: UNNotificationSound.lowGlucose)

                case defaults[.highAlertLevel]... where !defaults[.didAlertEvent] && trend > 0.25:
                    defaults[.didAlertEvent] = true
                    showAlert(title: "High Glucose", body: nil, sound: UNNotificationSound.highGlucose)

                case defaults[.lowAlertLevel] ..< defaults[.highAlertLevel]:
                    defaults[.didAlertEvent] = false

                default:
                    break
                }
            }
            if WCSession.default.isComplicationEnabled {
                var payload: [String:Any] = ["d": current.date.timeIntervalSince1970]
                switch Int(current.value) {
                case 180 ..< 250:
                    payload["v"] = "H"

                case 250...:
                    payload["v"] = "H+"

                case 75 ..< 180:
                    payload["v"] = "Ok"

                default:
                    payload["v"] = "\(Int(round(current.value)))"
                }
                if let v = payload["v"] as? String, v != watchState {
                    let now = Date()
                    let nowTime = now.hour * 60 + now.minute
                    if nowTime > defaults[.watchWakeupTime] && nowTime < defaults[.watchSleepTime] {
                        watchState = v
                        WCSession.default.transferCurrentComplicationUserInfo(payload)
                    }
                }
            }
        }
    }
}

extension UIApplication {
    static var theDelegate: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }
}
