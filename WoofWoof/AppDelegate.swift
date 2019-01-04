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

    override init() {
        super.init()
        UserDefaults.standard.lastStatisticsCalculation = nil
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
            let currentValue = MiaoMiao.trend?.last?.value ?? 100
            let newValue = currentValue + Double(arc4random_uniform(9)) - 4
            let gp = GlucosePoint(date: Date(), value: newValue)
            MiaoMiao.currentGlucose = gp
            MiaoMiao.trend = [gp]
            for _ in 0 ..< 14 {
                MiaoMiao.trend?.append(gp)
            }
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
}


extension AppDelegate: MiaoMiaoDelegate {
    func didUpdateGlucose() {
        if WCSession.default.isComplicationEnabled, let current = MiaoMiao.trend?.first {
            WCSession.default.transferCurrentComplicationUserInfo(["d": current.date.timeIntervalSince1970, "v": current.value, "c":true])
        }
    }
}
