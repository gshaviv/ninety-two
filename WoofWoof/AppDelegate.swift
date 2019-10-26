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
    var didAlertEvent: Bool {
        if let last = defaults[.lastEventAlertTime] {
            guard let level = MiaoMiao.currentGlucose?.value, let trend = currentTrend else {
                return true
            }
            return Date() - last < 15.m && (level > defaults[.highAlertLevel] ? level > defaults[.lastEventAlertLevel] || trend > 0.25 : level < defaults[.lastEventAlertLevel] || trend < 0.1)
        }
        return false
    }
    var sent: [StateKey: AnyHashable] = [:]
    let sentQueue = DispatchQueue(label: "sent", qos: .default, autoreleaseFrequency: .workItem)
    var complicationState: String {
        guard let current = MiaoMiao.currentGlucose else {
            return "-"
        }
        var show: String
        switch current.value {
        case defaults[.maxRange]...:
            let highest = MiaoMiao.allReadings.count > 6 ? MiaoMiao.allReadings[(MiaoMiao.allReadings.count - 6) ..< (MiaoMiao.allReadings.count - 2)].reduce(0.0) { max($0, $1.value) } : MiaoMiao.allReadings.last?.value ?? defaults[.maxRange]
            if current.value > highest {
                show = "\(current.value > 250 ? "H" : "h")⤴︎"
            } else {
                show = "\(current.value > 250 ? "H" : "h")⤵︎"
            }
            
            
        case defaults[.lowAlertLevel] ..< defaults[.maxRange]:
            show = "✔︎"
            
        default:
            guard let trend = MiaoMiao.trend else {
                return "-"
            }
            let lowest = min(trend[1...].reduce(100.0) { min($0, $1.value) }, MiaoMiao.last24hReadings[(max(MiaoMiao.last24hReadings.count - 6,0))...].reduce(100.0) { min($0, $1.value) })
            let sym: String
            if current.value < lowest {
                sym = "⤵︎"
            } else {
                sym = "⤴︎"
            }
            if WCSession.default.remainingComplicationUserInfoTransfers < 10 && WCSession.default.remainingComplicationUserInfoTransfers > 0 {
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
        if WCSession.default.remainingComplicationUserInfoTransfers == 1 {
            show = "❌"
        }
        return show
    }
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
                GlucosePoint(date: Date() - 4.m, value: currentValue + Double(arc4random_uniform(100)) / 50 - 1)].reversed()
            MiaoMiao.last24hReadings = MiaoMiao.last24hReadings.filter { $0.date < MiaoMiao.trend!.first!.date }
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
            if MiaoMiao.sensorState != .unknown {
            sendAppState()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        log("WCSession inactive")
        markSendAll()
    }

    
    func sessionDidDeactivate(_ session: WCSession) {
    }

    func appState() -> [StateKey:AnyHashable] {
        let now = Date()
        let lastSent = Date(timeIntervalSince1970: (sent[.history] as? [[Double]])?.last?.first ?? 0.0)
        let firstTrend = MiaoMiao.trend?.last?.date ?? Date.distantFuture
        let points = MiaoMiao.last24hReadings.filter { $0.date > now - 3.h - 16.m && $0.date > lastSent && $0.date < firstTrend - 2.m && $0.type == .history }.map { [$0.date.timeIntervalSince1970, $0.value] }
        let when = Date() - (defaults[.delayMinutes] + defaults[.diaMinutes]) * 60
        let events = Storage.default.allEntries.filter { $0.bolus > 0 && $0.date > when }.map { [$0.date.timeIntervalSince1970, Double($0.bolus)] }
        var state:[StateKey:AnyHashable] = [
            .change: currentTrend ?? 0,
            .sensorStart: defaults[.sensorBegin] ?? Date(),
            .battery: MiaoMiao.batteryLevel,
            .complication: complicationState,
            .events: events
        ]
        var trendToSend = [GlucosePoint]()
        var last = Date.distantFuture
        for point in MiaoMiao.trend ?? [] {
            if point.date < last {
                last = point.date - (2⁚30).s
                trendToSend.insert(point, at: 0)
            }
        }
        if !trendToSend.isEmpty {
        state[.trend] = trendToSend.map { [$0.date.timeIntervalSince1970, $0.value ]}
        }
        if !points.isEmpty {
            state[.history] = points
        }
        let watchDefaults = [
            UserDefaults.DoubleKey.level0.key, UserDefaults.ColorKey.color0.key,
            UserDefaults.DoubleKey.level1.key, UserDefaults.ColorKey.color1.key,
            UserDefaults.DoubleKey.level2.key, UserDefaults.ColorKey.color2.key,
            UserDefaults.DoubleKey.level3.key, UserDefaults.ColorKey.color3.key,
            UserDefaults.DoubleKey.level4.key, UserDefaults.ColorKey.color4.key,
            UserDefaults.ColorKey.color5.key,
            UserDefaults.DoubleKey.delayMinutes.key,
            UserDefaults.DoubleKey.peakMinutes.key,
            UserDefaults.DoubleKey.diaMinutes.key
        ]
        var defaultValues = [String:AnyHashable]()
        for key in watchDefaults {
            defaultValues[key] = defaults.value(forKey: key) as? AnyHashable
        }
        state[.defaults] = defaultValues
        if summary.data.period > 0 {
            do {
                let data = try JSONEncoder().encode(summary.data)
                if let str = String(data: data, encoding: .utf8)  {
                    state[.summary] = str
                }
            } catch {}
        }
        
        return state
    }
    
    func filteredState(_ inState: [StateKey: AnyHashable]) -> [StateKey: AnyHashable] {
        var state = inState
        sentQueue.sync {
            for key in state.keys {
                if let old = self.sent[key], let current = state[key], old == current {
                    state[key] = nil
                }
            }
        }
        return state
    }
    
    func jsonState(_ state: [StateKey: AnyHashable]) -> String {
        var jValues = [String]()
        for (key,value) in state {
            switch value {
            case let v as [[Double]]:
                var outer = [String]()
                for outerV in v {
                    var inner = [String]()
                    for innerV in outerV {
                        inner.append(innerV.decimal(digits: 2).description)
                    }
                    outer.append("[\(inner.joined(separator: ","))]")
                }
                jValues.append("\"\(key.rawValue)\":[\(outer.joined(separator: ","))]")
                
            case let v as Double:
                jValues.append("\"\(key.rawValue)\":\(v.decimal(digits: 1))")
                
            case let v as String:
                jValues.append("\"\(key.rawValue)\":\"\(v.replacingOccurrences(of: "\"", with: "\\\""))\"")
                
            case let v as Int:
                jValues.append("\"\(key.rawValue)\":\(v)")

            case let v as Date:
                jValues.append("\"\(key.rawValue)\":\(v.timeIntervalSince1970.decimal(digits: 0))")

            default:
                break
            }
        }
        return "{\(jValues.joined(separator: ","))}"
    }
    
    func markSent(_ state: [StateKey:AnyHashable]) {
        sentQueue.async {
            state.forEach { self.sent[$0.key] = $0.value }
        }
    }
    
    func markSendSummary() {
        sentQueue.async {
            self.sent[.summary] = nil
        }
    }
    func markSendDefaults() {
        sentQueue.async {
            self.sent[.defaults] = nil
        }
    }

    func markSendState() {
        
    }
    func markSendAll() {
        sentQueue.async {
            self.sent = [:]
        }
    }

    func sendAppState(_ inState: [StateKey:AnyHashable]? = nil) {
        DispatchQueue.main.async {
            do {
                let state = self.filteredState(inState ?? self.appState())
                try WCSession.default.updateApplicationContext(state.withStringKeys())
                log("Sent [\(state.keys.map { String(describing:$0).replacingOccurrences(of: "WoofKit.StateKey.", with: "") }.sorted().joined(separator: ", "))]")
                self.markSent(state)
            } catch { }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let ops = message["op"] as? [String] else {
            return
        }
        DispatchQueue.main.async {
            log("Watch message: \(ops.joined(separator: ", "))")
            var sendState = false
            ops.forEach {
                switch $0 {
                case "state":
                    self.markSendState()
                    sendState = true
                    
                case "fullState":
                    self.markSendState()
                    self.sentQueue.sync {
                        for k in [StateKey.history, StateKey.trend, StateKey.battery, StateKey.sensorStart, StateKey.events] {
                            self.sent[k] = nil
                        }
                    }
                    sendState = true
                    
                    
                case "defaults":
                    self.markSendDefaults()
                    sendState = true
                    
                case "summary":
                    self.markSendSummary()
                    sendState = true
                    let bgt = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                    summary.update(force: true) {
                        if $0 {
                            self.sendAppState()
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
                        if UIApplication.shared.applicationState != .background, let nav = self.window?.rootViewController as? UINavigationController, let ctr = nav.viewControllers.first as? ViewController {
                            ctr.update()
                        }
                    }
                    
                default:
                    break
                }
            }
            if sendState {
                var reply = self.filteredState(self.appState())
                if reply[.complication] == nil && ops.contains("fullState") {
                    reply[.complication] = self.complicationState
                }
                log("reply -> [\(reply.keys.map { String(describing:$0).replacingOccurrences(of: "WoofKit.StateKey.", with: "") }.sorted().joined(separator: ", "))]")
                replyHandler(reply.withStringKeys())
                self.markSent(reply)
            } else {
                replyHandler([:])
            }
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
            defaults[.lastEventAlertLevel] = MiaoMiao.currentGlucose?.value ?? 100
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
                log("\(current.value % ".02lf")\(trendSymbol(for: trend)) \(trend > 0 ? "+" : "")\(trend % ".02lf")")
            }
            if let sharedDb = self.sharedDb {
                DispatchQueue.global().async {
                    var error: NSError?
                    self.coordinator.coordinate(writingItemAt: sharedDbUrl, options: [], error: &error, byAccessor: { (_) in
                        do {
                            try sharedDb.transaction { db in
                                try? db.execute("delete from \(GlucosePoint.tableName)")
                                let now = Date()
                                if let relevant = MiaoMiao.allReadings.filter({ $0.date > now - 4.h && $0.type != .calibration }) as? [GlucosePoint] {
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
                    showAlert(title: "Low Glucose", body: "Current level is \(current.value % ".0lf")", sound: UNNotificationSound.lowGlucose)
                    
                case defaults[.highAlertLevel]... where !didAlertEvent && trend > 0.25:
                    showAlert(title: "High Glucose", body: "Current level is \(current.value % ".0lf")", sound: UNNotificationSound.highGlucose)
                    
                case defaults[.lowAlertLevel] ..< defaults[.highAlertLevel]:
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationIdentifier.event])
                    defaults[.lastEventAlertTime] = nil
                    
                default:
                    break
                }
            }
            if WCSession.default.activationState == .activated {
                if WCSession.default.isReachable {
                    sendAppState()
                }
                var payload: [StateKey: AnyHashable] = [.currentDate: current.date.timeIntervalSince1970]
                switch current.value {
                case defaults[.maxRange]...:
                    let highest = MiaoMiao.allReadings.count > 6 ? MiaoMiao.allReadings[(MiaoMiao.allReadings.count - 6) ..< (MiaoMiao.allReadings.count - 2)].reduce(0.0) { max($0, $1.value) } : MiaoMiao.allReadings.last?.value ?? defaults[.maxRange]
                    if current.value > highest {
                        if let last = defaults[.lastEventAlertTime], Date() > last + 10.m {
                            showAlert(title: "New High Level", body: "Current glucose level is \(Int(current.value))", sound: nil)
                        }
                    }
                    
                    
                case defaults[.lowAlertLevel] ..< defaults[.maxRange]:
                    break
                    
                default:
                    if let last = defaults[.lastEventAlertTime], Date() > last + 10.m, let currentTrend = currentTrend, currentTrend < 0 {
                        showAlert(title: "Low & dropping", body: "Current glucose level is \(Int(current.value))", sound: nil)
                    }
                }
                
                DispatchQueue.main.async {
                    if  WCSession.default.isComplicationEnabled && self.complicationState != self.sent[.complication] as? String ?? "!" {
                        payload[.complication] = self.complicationState
                        self.markSent(payload)
                        WCSession.default.transferCurrentComplicationUserInfo(payload.withStringKeys())
                    }
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
