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
import Sqlable
import WoofKit

private let sharedDbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "5h.sqlite"))


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    #if targetEnvironment(simulator)
        var updater: Repeater?
    #endif
    private(set) public var trendCalculator: Calculation<Double?>!
    private let sharedDb: SqliteDatabase? = {
        let db = try? SqliteDatabase(filepath: sharedDbUrl.path)
        try! db?.createTable(GlucosePoint.self)
        return db
    }()
    private let sharedOperationQueue = OperationQueue()
    private var coordinator: NSFileCoordinator!
    override init() {
        super.init()
        defaults[.lastStatisticsCalculation] = nil
        trendCalculator = Calculation {
            return self.trendValue()
        }
        defaults.register()
        coordinator = NSFileCoordinator(filePresenter: self)
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
                                  GlucosePoint(date: Date() - 1.m, value: newValue + Double(arc4random_uniform(100)) / 50 - 1),
                                  GlucosePoint(date: Date() - 2.m, value: newValue + Double(arc4random_uniform(100)) / 50 - 1),
                                  GlucosePoint(date: Date() - 3.m, value: newValue + Double(arc4random_uniform(100)) / 50 - 1),
                                  GlucosePoint(date: Date() - 4.m, value: newValue + Double(arc4random_uniform(100)) / 50 - 1)]

                DispatchQueue.main.async {
                    MiaoMiao.delegate?.forEach { $0.didUpdate(addedHistory: [gp]) }
                }
                if Date() - lastHistoryDate > 5.m {
                    MiaoMiao.last24hReadings.append(gp)
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
        let midnight = Date().midnightBefore
        Storage.default.todayBolus = Storage.default.db.evaluate(Bolus.read().filter(Bolus.date > midnight)) ?? []
        Storage.default.meals = Storage.default.db.evaluate(Meal.read().filter(Bolus.date > midnight)) ?? []
        if let nav = window?.rootViewController as? UINavigationController, let ctr = nav.viewControllers.first as? ViewController  {
            ctr.graphView.meals = Storage.default.meals
            ctr.graphView.boluses = Storage.default.todayBolus
        }
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
            var weightSum:Double = 0
            var weight:Double = 0
            log("Last trend diffs = \(diffs[0 ..< 4].map { -$0 })")
            let sum = diffs[0 ..< 4].reversed().reduce(0.0) {
                weight += 1
                weightSum += weight
                return $0 + $1 * weight
            }
            log("trend is \(-sum / weightSum)")
            return -sum / weightSum
        }
        return nil
    }

    func trendSymbol(for inputTrend: Double? = nil) -> String {
        guard let trend = inputTrend ?? trendCalculator.value else {
            return ""
        }
        if trend > 2.0 {
            return "⇈"
        } else if trend > 1.0 {
            return "↑"
        } else if trend > 0.4 {
            return "↗︎"
        } else if trend > -0.4 {
            return "→"
        } else if trend > -1.0 {
            return "↘︎"
        } else if trend > -2.0 {
            return "↓"
        } else {
            return "⇊"
        }
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let nav = window?.rootViewController as? UINavigationController, let ctr = nav.viewControllers.first as? ViewController else {
            return false
        }
        switch userActivity.activityType {
        case "BolusIntent":
            ctr.addBolus(units: (userActivity.interaction?.intent.value(forKey: "units") as? NSNumber)?.intValue)

        case "MealIntent":
            var kind: Meal.Kind? = nil
            if let k = (userActivity.interaction?.intent.value(forKey: "type") as? NSNumber)?.intValue {
                kind = Meal.Kind(rawValue: k - 1)
            }
            ctr.addMeal(kind: kind)

        default:
            break
        }
        return true
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
            WCSession.default.transferUserInfo(["d": current.date.timeIntervalSince1970, "v": current.value, "c": true])
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
    }

    func appState() -> [String:Any] {
        let now = Date()
        let relevant = MiaoMiao.allReadings.filter { $0.date > now - 4.h && !$0.isCalibration }.map { [$0.date, $0.value] }
        let state:[String:Any] = ["v": relevant, "t": trendValue() ?? 0, "s": trendSymbol()]
        return state
    }

    func sendAppState() {
        try? WCSession.default.updateApplicationContext(appState())
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let op = message["op"] as? String else {
            return
        }
        switch op {
        case "state":
            replyHandler(appState())

        default:
            break
        }
    }
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
            defaults[.lastEventAlertTime] = Date()
            notification.categoryIdentifier = "event"
            let request = UNNotificationRequest(identifier: NotificationIdentifier.event, content: notification, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                if let err = err {
                    logError("\(err)")
                }
            })
        }
    }

    func didUpdate(addedHistory: [GlucosePoint]) {
        trendCalculator.invalidate()
        if let current = MiaoMiao.currentGlucose {
            if let sharedDb = self.sharedDb {
                DispatchQueue.global().async {
                    var error: NSError?
                    self.coordinator.coordinate(writingItemAt: sharedDbUrl, options: [], error: &error, byAccessor: { (_) in
                        do {
                            try sharedDb.beginTransaction()
                            try? sharedDb.execute("delete from \(GlucosePoint.tableName)")
                            let now = Date()
                            if let relevant = MiaoMiao.allReadings.filter({ $0.date > now - 4.h && !$0.isCalibration }) as? [GlucosePoint] {
                                relevant.forEach { sharedDb.evaluate($0.insert()) }
                            }
                            try sharedDb.commitTransaction()
                        } catch {}
                    })
                }
            }
            if let trend = trendValue() {
                switch current.value {
                case ...defaults[.lowAlertLevel] where !defaults[.didAlertEvent] && trend < -0.25:
                    defaults[.didAlertEvent] = true
                    showAlert(title: "Low Glucose", body: nil, sound: UNNotificationSound.lowGlucose)

                case defaults[.highAlertLevel]... where !defaults[.didAlertEvent] && trend > 0.25:
                    defaults[.didAlertEvent] = true
                    showAlert(title: "High Glucose", body: "Current level is \(Int(current.value))", sound: UNNotificationSound.highGlucose)

                case defaults[.lowAlertLevel] ..< defaults[.highAlertLevel]:
                    defaults[.didAlertEvent] = false
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationIdentifier.event])

                default:
                    break
                }
            }
            if WCSession.default.activationState == .activated {
                if  WCSession.default.isComplicationEnabled {
                    var payload: [String: Any] = ["d": current.date.timeIntervalSince1970]
                    var show: String
                    switch Int(current.value) {
                    case 180...:
                        guard let trend = MiaoMiao.trend else {
                            return
                        }
                        let highest = max(trend[1...].reduce(0.0) { max($0, $1.value) }, MiaoMiao.last24hReadings[(MiaoMiao.last24hReadings.count - 6)...].reduce(0.0) { max($0, $1.value) })
                        if current.value > highest {
                            show = "\(current.value > 250 ? "H" : "h")⤴︎"
                            if let last = defaults[.lastEventAlertTime], Date() > last + 10.m {
                                showAlert(title: "New High Level", body: "Current glucose level is \(Int(current.value))", sound: nil)
                            }
                        } else {
                            show = "\(current.value > 250 ? "H" : "h")⤵︎"
                        }


                    case 75 ..< 180:
                        show = "✔︎"

                    default:
                        guard let trend = MiaoMiao.trend else {
                            return
                        }
                        let lowest = min(trend[1...].reduce(100.0) { min($0, $1.value) }, MiaoMiao.last24hReadings[(max(MiaoMiao.last24hReadings.count - 6,0))...].reduce(100.0) { min($0, $1.value) })
                        let sym: String
                        if current.value < lowest {
                            sym = "⤵︎"
                        } else {
                            sym = "⤴︎"
                        }
                        if WCSession.default.remainingComplicationUserInfoTransfers < 10 {
                            show = "L\(sym)"
                        } else {
                            let level = Int(ceil(round(current.value) / 5) * 5)
                            show = "≤\(level)"
                        }
                    }
                    let now = Date()
                    let nowTime = now.hour * 60 + now.minute
                    if nowTime < defaults[.watchWakeupTime] || nowTime > defaults[.watchSleepTime] {
                        show = "🌘"
                    }
                    if show != defaults[.complicationState] {
                        if WCSession.default.remainingComplicationUserInfoTransfers == 1 {
                            show = "❌"
                        }
                        defaults[.complicationState] = show
                        payload["v"] = show
                        WCSession.default.transferCurrentComplicationUserInfo(payload)
                    }
                }
                if WCSession.default.isReachable {
                    sendAppState()
                }
            }
        }
    }
}


extension AppDelegate: NSFilePresenter {
    var presentedItemURL: URL? {
        return sharedDbUrl
    }

    var presentedItemOperationQueue: OperationQueue {
        return sharedOperationQueue
    }
}

extension UIApplication {
    static var theDelegate: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }
}


class NotificationIdentifier {
    static let noSensor = "noSensor"
    static let event = "event"
    static let lowBattery = "lowBattery"
    static let noData = "noData"
    static let calibrate = "calibrate"
}

extension Measurement {
    var glucosePoint: GlucosePoint {
        return GlucosePoint(date: date, value: temperatureAlgorithmGlucose)
    }
}

extension UNNotificationSound {
    public static let calibrationNeeded = UNNotificationSoundName(rawValue: "Siri_Calibration_Needed.caf")
    public static let lowGlucose = UNNotificationSoundName(rawValue: "Siri_Low_Glucose.caf")
    public static let highGlucose = UNNotificationSoundName(rawValue: "Siri_High_Glucose.caf")
    public static let missed = UNNotificationSoundName(rawValue: "Siri_Missed_Readings.caf")
}
