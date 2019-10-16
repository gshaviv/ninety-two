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
import Zip
import AudioToolbox
import BackgroundTasks

private let sharedDbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "5h.sqlite"))


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var didAlertEvent = false
    var sent: [String: AnyHashable] = [:]
    let sentQueue = DispatchQueue(label: "sent", qos: .default, autoreleaseFrequency: .workItem)
    var complicationState = "--"
    var window: UIWindow? {
        didSet {
            window?.tintColor = #colorLiteral(red: 0.1960784346, green: 0.3411764801, blue: 0.1019607857, alpha: 1)
        }
    }
    #if targetEnvironment(simulator)
        var updater: Repeater?
    #endif
    private(set) public var trendCalculator: Calculation<Double?>!
    public var currentTrend: Double? {
        return trendCalculator.value
    }
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

        try! Storage.default.db.createTable(FoodServing.self)
        try! Storage.default.db.createTable(Meal.self)
        WCSession.default.delegate = self
        WCSession.default.activate()

        MiaoMiao.addDelegate(self)

        #if targetEnvironment(simulator)
        var lastHistoryDate = Date() - 15.m
        var currentValue = Double.random(in: 80...160)
        MiaoMiao.last24hReadings.append(GlucosePoint(date: lastHistoryDate, value: currentValue))
        var trend = Bool.random() ? -1.0 : 1.0
        
        updater = Repeater.every(60, perform: { (_) in
            currentValue += trend * Double.random(in: 0..<3)
            if Double.random(in: 0..<1) < 0.2 {
                trend *= -1
            }
            if currentValue < 60 {
                trend = 1
            } else if currentValue > 200 {
                trend = -1
            }
            let gp = GlucosePoint(date: Date(), value: currentValue)
            MiaoMiao.trend = [gp,
                              GlucosePoint(date: Date() - 1.m, value: currentValue + Double(arc4random_uniform(100)) / 50 - 1),
                              GlucosePoint(date: Date() - 2.m, value: currentValue + Double(arc4random_uniform(100)) / 50 - 1),
                              GlucosePoint(date: Date() - 3.m, value: currentValue + Double(arc4random_uniform(100)) / 50 - 1),
                              GlucosePoint(date: Date() - 4.m, value: currentValue + Double(arc4random_uniform(100)) / 50 - 1)]
            MiaoMiao.last24hReadings.append(gp)
            lastHistoryDate = Date()
            DispatchQueue.main.async {
                MiaoMiao.delegate?.forEach { $0.didUpdate(addedHistory: [gp]) }
            }
        })
        #endif
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.tivstudio.92.estimate", using: DispatchQueue.global()) { (task) in
            RecordViewController.createmodel()
            task.setTaskCompleted(success: true)
        }

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        MiaoMiao.unloadMemory()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Storage.default.reloadToday()
        if let nav = window?.rootViewController as? UINavigationController, let ctr = nav.viewControllers.first as? ViewController  {
            ctr.graphView.records = Storage.default.lastDay.entries
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if url.isFileURL {
            if url.pathExtension == "zip" {
                DispatchQueue.global().async {
                    _ = url.startAccessingSecurityScopedResource()
                    do {
                        let outputDir = try Zip.quickUnzipFile(url)
                        try FileManager.default.removeItem(at: url)
                        url.stopAccessingSecurityScopedResource()
                        let path = outputDir.appendingPathComponent("read.sqlite").path
                        if  !FileManager.default.fileExists(atPath: path) {
                            DispatchQueue.main.async {
                                let notification = UNMutableNotificationContent()
                                notification.title = "Datebase not found"
                                notification.body = "Imported zip file does not contain any database"
                                notification.categoryIdentifier = NotificationIdentifier.error
                                let request = UNNotificationRequest(identifier: NotificationIdentifier.error, content: notification, trigger: nil)
                                UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                                    if let err = err {
                                        logError("\(err)")
                                    }
                                })
                            }
                            return
                        }
                        let importDb = try SqliteDatabase(filepath: path)
                        let readings = importDb.evaluate(GlucosePoint.read()) ?? []
                        var mealCount = 0
                        var readingCount = 0
                        try Storage.default.db.transaction { (db)  in
                            do {
                                let have = db.evaluate(GlucosePoint.read()) ?? []
                                let all = Set(have.map { $0.date })
                                for gp in readings {
                                    if !all.contains(gp.date) {
                                        try db.perform(gp.insert())
                                        readingCount += 1
                                    }
                                }
                            }
                            do {
                                let have = db.evaluate(ManualMeasurement.read()) ?? []
                                let all = Set(have.map { $0.date })
                                for gp in importDb.evaluate(ManualMeasurement.read()) ?? [] {
                                    if !all.contains(gp.date) {
                                        try db.perform(gp.insert())
                                        readingCount += 1
                                    }
                                }
                            }

                            let meals = importDb.evaluate(Record.read()) ?? []
                            let existingMeals = Set(db.evaluate(Record.read()) ?? [])
                            for record in meals {
                                if !existingMeals.contains(record) {
                                    try db.perform(record.insert())
                                    mealCount += 1
                                }
                            }

                            do {
                                let cals = db.evaluate(Calibration.read()) ?? []
                                let allCalibs = Set(cals.map { $0.date })
                                let imported = importDb.evaluate(Calibration.read()) ?? []
                                for row in imported {
                                    if !allCalibs.contains(row.date) {
                                        try db.perform(row.insert())
                                    }
                                }
                            }
                        }
                        try Storage.default.db.execute("vacuum")
                        DispatchQueue.main.async {
                            let notification = UNMutableNotificationContent()
                            if mealCount > 0 || readingCount > 0 {
                                notification.title = "Imported"
                                notification.body = "Imported \(readingCount) readings and \(mealCount) diary entries"
                            } else {
                                notification.title = "Nothing to Import"
                                notification.body = "No missing records in existing database"
                            }
                            notification.categoryIdentifier = NotificationIdentifier.imported
                            let request = UNNotificationRequest(identifier: NotificationIdentifier.imported, content: notification, trigger: nil)
                            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                                if let err = err {
                                    logError("\(err)")
                                }
                            })
                        }
                    } catch {
                        url.stopAccessingSecurityScopedResource()
                        DispatchQueue.main.async {
                            let notification = UNMutableNotificationContent()
                            notification.title = "Error Importing"
                            notification.body = error.localizedDescription
                            notification.categoryIdentifier = NotificationIdentifier.error
                            let request = UNNotificationRequest(identifier: NotificationIdentifier.error, content: notification, trigger: nil)
                            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                                if let err = err {
                                    logError("\(err)")
                                }
                            })
                        }
                    }
                }
            }
            return true
        }
        return false
    }

    private func trendValue() -> Double? {
        guard let trend = MiaoMiao.trend, trend.count > 3, let last = trend.last else {
            return nil
        }
        let base = last.value > 70 ? 3 : 1
        return (trend[0].value - trend[base].value) / (trend[0].date - trend[base].date) * 60
    }

    func trendSymbol(for inputTrend: Double? = nil) -> String {
        guard let trend = inputTrend ?? currentTrend else {
            return ""
        }
        return WoofWoof.trendSymbol(for: trend)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let nav = window?.rootViewController as? UINavigationController, let ctr = nav.viewControllers.first as? ViewController else {
            return false
        }
        switch userActivity.activityType {
        case "DiaryIntent":
            ctr.addRecord(meal: Record.MealType(name: userActivity.interaction?.intent.value(forKey: "meal") as? String), units: (userActivity.interaction?.intent.value(forKey: "units") as? NSNumber)?.intValue, note: userActivity.interaction?.intent.value(forKey: "note") as? String)

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

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let nav = window?.rootViewController as? UINavigationController, let ctr = nav.viewControllers.first as? ViewController else {
            return
        }
        switch response.notification.request.identifier {
        case NotificationIdentifier.calibrate:
            ctr.calibrate()

        case NotificationIdentifier.noData:
            defaults[.nextNoSensorAlert] = Date()
            Central.manager.restart()

        default:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {

    }
}

extension AppDelegate: WCSessionDelegate {
    

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            log("WCSession activated")
            markSendAll()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        log("WCSession inactive")
        markSendAll()
    }

    
    func sessionDidDeactivate(_ session: WCSession) {
    }

    func appState() -> [String:AnyHashable] {
        let now = Date()
        let points = MiaoMiao.allReadings.filter { $0.date > now - 3.h - 16.m && !$0.isCalibration }.map { [$0.date.timeIntervalSince1970, $0.value] }
        var state:[String:AnyHashable] = [
            "v": points,
            "t": currentTrend ?? 0,
            "s": trendSymbol(),
            "age": defaults[.sensorBegin] ?? Date(),
            "b": MiaoMiao.batteryLevel,
            "c": complicationState,
            "iob": Storage.default.insulinOnBoard(at: now),
        ]
        if points.isEmpty {
            state["v"] = nil
        }
        let watchDefaults = [
            UserDefaults.DoubleKey.level0.key, UserDefaults.ColorKey.color0.key,
            UserDefaults.DoubleKey.level1.key, UserDefaults.ColorKey.color1.key,
            UserDefaults.DoubleKey.level2.key, UserDefaults.ColorKey.color2.key,
            UserDefaults.DoubleKey.level3.key, UserDefaults.ColorKey.color3.key,
            UserDefaults.DoubleKey.level4.key, UserDefaults.ColorKey.color4.key,
            UserDefaults.ColorKey.color5.key
        ]
        var defaultValues = [String:AnyHashable]()
        for key in watchDefaults {
            defaultValues[key] = defaults.value(forKey: key) as? AnyHashable
        }
        state["defaults"] = defaultValues
        if summary.data.period > 0 {
            do {
                let data = try JSONEncoder().encode(summary.data)
                if let str = String(data: data, encoding: .utf8)  {
                    state["summary"] = str
                }
            } catch {}
        }
        sentQueue.sync {
            for key in state.keys {
                if let old = self.sent[key], let current = state[key], old == current {
                    state[key] = nil
                }
            }
        }
        
        return state
    }
    
    func markSent(_ state: [String:AnyHashable]) {
        sentQueue.async {
            state.forEach { self.sent[$0.key] = $0.value }
        }
    }
    
    func markSendSummary() {
        sentQueue.async {
            self.sent["summary"] = nil
        }
    }
    func markSendDefaults() {
        sentQueue.async {
            self.sent["defaults"] = nil
        }
    }

    func markSendState() {
        sentQueue.async {
            for k in ["t","s","c"] {
                self.sent[k] = nil
            }
        }
    }
    func markSendAll() {
        sentQueue.async {
            self.sent = [:]
        }
    }

    func sendAppState() {
        do {
            let state = appState()
            try WCSession.default.updateApplicationContext(state)
            log("Sent \(state.keys.sorted())")
            markSent(state)
        } catch { }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let ops = message["op"] as? [String] else {
            return
        }
        log("Watch request: \(ops.joined(separator: ", "))")
        var sendState = false
        ops.forEach {
            switch $0 {
            case "state":
                markSendState()
                sendState = true
                
            case "fullState":
                markSendState()
                sentQueue.sync {
                    for k in ["v","b","age"] {
                        self.sent[k] = nil
                    }
                }
                sendState = true

                
            case "defaults":
                markSendDefaults()
                sendState = true

            case "summary":
                markSendSummary()
                sendState = true
                let bgt = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                summary.update(force: true) {
                    if $0 {
                        self.updateSummary()
                    }
                    UIApplication.shared.endBackgroundTask(bgt)
                }

            case "reconnect":
                Central.manager.restart()
                
            case "read":
                MiaoMiao.Command.startReading()
                
            case "calibrate":
                if let v = message["value"] as? Double {
                    MiaoMiao.addCalibration(value: v)
                    if UIApplication.shared.applicationState != .background, let nav = window?.rootViewController as? UINavigationController, let ctr = nav.viewControllers.first as? ViewController {
                        ctr.update()
                    }
                }
                
            default:
                break
            }
        }
        if sendState {
            let reply = appState()
            log("reply -> \(reply.keys.sorted())")
            replyHandler(reply)
            markSent(reply)
        } else {
            replyHandler([:])
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
            notification.categoryIdentifier = NotificationIdentifier.event
            let request = UNNotificationRequest(identifier: NotificationIdentifier.event, content: notification, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                if let err = err {
                    logError("\(err)")
                }
            })
            if defaults[.alertVibrate] {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }

    func didUpdate(addedHistory: [GlucosePoint]) {
        trendCalculator.invalidate()
        if let current = MiaoMiao.currentGlucose {
            if let trend = currentTrend {
                log("\(current.value % ".02lf")\(trendSymbol(for: currentTrend)) \(trend > 0 ? "+" : "")\(trend % ".02lf")")
            }
            if let sharedDb = self.sharedDb {
                DispatchQueue.global().async {
                    var error: NSError?
                    self.coordinator.coordinate(writingItemAt: sharedDbUrl, options: [], error: &error, byAccessor: { (_) in
                        do {
                            try sharedDb.transaction { db in
                                try? db.execute("delete from \(GlucosePoint.tableName)")
                                let now = Date()
                                if let relevant = MiaoMiao.allReadings.filter({ $0.date > now - 4.h && !$0.isCalibration }) as? [GlucosePoint] {
                                    relevant.forEach { db.evaluate($0.insert()) }
                                }
                            }
                        } catch {}
                    })
                }
            }
            if let trend = currentTrend {
                switch current.value {
                case ...defaults[.lowAlertLevel] where !didAlertEvent && trend < -0.25:
                    didAlertEvent = true
                    showAlert(title: "Low Glucose", body: "Current level is \(current.value % ".0lf")", sound: UNNotificationSound.lowGlucose)

                case defaults[.highAlertLevel]... where !didAlertEvent && trend > 0.25:
                    didAlertEvent = true
                    showAlert(title: "High Glucose", body: "Current level is \(current.value % ".0lf")", sound: UNNotificationSound.highGlucose)

                case defaults[.lowAlertLevel] ..< defaults[.highAlertLevel]:
                    didAlertEvent = false
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationIdentifier.event])

                default:
                    break
                }
            }
            if WCSession.default.activationState == .activated {
                if  WCSession.default.isComplicationEnabled {
                    var payload: [String: Any] = ["d": current.date.timeIntervalSince1970]
                    var show: String
                    switch current.value {
                    case defaults[.maxRange]...:
                        let highest = MiaoMiao.allReadings.count > 6 ? MiaoMiao.allReadings[(MiaoMiao.allReadings.count - 6) ..< (MiaoMiao.allReadings.count - 2)].reduce(0.0) { max($0, $1.value) } : MiaoMiao.allReadings.last?.value ?? defaults[.maxRange]
                        if current.value > highest {
                            show = "\(current.value > 250 ? "H" : "h")⤴︎"
                            if let last = defaults[.lastEventAlertTime], Date() > last + 10.m {
                                showAlert(title: "New High Level", body: "Current glucose level is \(Int(current.value))", sound: nil)
                            }
                        } else {
                            show = "\(current.value > 250 ? "H" : "h")⤵︎"
                        }


                    case defaults[.lowAlertLevel] ..< defaults[.maxRange]:
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
                        if let last = defaults[.lastEventAlertTime], Date() > last + 10.m, let currentTrend = currentTrend, currentTrend < 0 {
                            showAlert(title: "Low & dropping", body: "Current glucose level is \(Int(current.value))", sound: nil)
                        }
                    }
                    let now = Date()
                    let nowTime = now.hour * 60 + now.minute
                    if nowTime < defaults[.watchWakeupTime] || nowTime > defaults[.watchSleepTime] {
                        show = "🌘"
                    }
                    if show != sent["c"] as? String ?? "!" {
                        if WCSession.default.remainingComplicationUserInfoTransfers == 1 {
                            show = "❌"
                        }
                        complicationState = show
                        sent["c"] = show
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

extension AppDelegate {
    func defaultsMessage() -> [String:AnyHashable] {
        return ["defaults": defaults.dictionaryRepresentation() as! [String:AnyHashable]]
    }
    func updateDefaults() {
        let message = defaultsMessage()
        WCSession.default.sendMessage(message, replyHandler: { (response) in
            self.markSent(message)
        }) { (_) in
        }
    }
    func summaryMessage() -> [String:AnyHashable] {
        do {
            let data = try JSONEncoder().encode(summary.data)
            guard let str = String(data: data, encoding: .utf8) else {
                return [:]
            }
            return ["summary": str]
        } catch {
            return [:]
        }
    }
    func updateSummary() {
        let message = summaryMessage()
        log("sending: [\"summary\"]")
        WCSession.default.sendMessage(message, replyHandler: { (response) in
            self.markSent(message)
        }) { (_) in
        }
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
    static let newSensor = "newSensor"
    static let imported = "imported"
    static let error = "error"
}

extension Measurement {
    var glucosePoint: GlucosePoint {
        return GlucosePoint(date: date, value: temperatureAlgorithmGlucose)
    }
    var trendPoint: GlucosePoint {
        return GlucosePoint(date: date, value: temperatureAlgorithmGlucose, isTrend: true)
    }
}

extension UNNotificationSound {
    public static let calibrationNeeded = UNNotificationSoundName(rawValue: "Siri_Calibration_Needed.caf")
    public static let lowGlucose = UNNotificationSoundName(rawValue: "Siri_Low_Glucose.caf")
    public static let highGlucose = UNNotificationSoundName(rawValue: "Siri_High_Glucose.caf")
    public static let missed = UNNotificationSoundName(rawValue: "Siri_Missed_Readings.caf")
}
