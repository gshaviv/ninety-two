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
import WoofKit
import Zip
import AudioToolbox
import BackgroundTasks
import WidgetKit
import GRDB
import OSLog


class MainOpener: DatabaseOpener {
    func openDatabase(at url: URL) throws -> DatabasePool {
        log("open main db at: \(url.path)")
        let db = try Storage.openSharedDatabase(at: url)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") {
            try GlucosePoint.createTable(in: $0)
            try Calibration.createTable(in: $0)
            try ManualMeasurement.createTable(in: $0)
            try Meal.createTable(in: $0)
            try Entry.createTable(in: $0)
            try FoodServing.createTable(in: $0)
        }
        try migrator.migrate(db)
        return db
    }
}

class TrendDBOpener: DatabaseOpener {
    func openDatabase(at url: URL) throws -> DatabasePool {
        let db = try Storage.openSharedDatabase(at: url)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") {
            try GlucosePoint.createTable(in: $0)
        }
        try migrator.migrate(db)
        return db
    }
}


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var didAlertEvent: Bool {
        if let last = defaults[.lastEventAlertTime] {
            guard let level = MiaoMiao.currentGlucose?.value, let trend = currentTrend else {
                return true
            }
            return Date() - last < 15.m || (level > defaults[.highAlertLevel] ?
                level > defaults[.lastEventAlertLevel] || trend > 0.25 :
                false)
        }
        return false
    }
    var sent: [StateKey: AnyHashable] = [:]
    let sentQueue = DispatchQueue(label: "sent", qos: .default, autoreleaseFrequency: .workItem)
    var clean = false
    var complicationState: String {
        guard let current = MiaoMiao.currentGlucose else {
            return "-"
        }
        var show: String
        let lowRange = "✔︎✔︎"
        let highRange = "✔︎"
        switch current.value {
        case defaults[.maxRange]...:
            let highest = MiaoMiao.allReadings.count > 6 ? MiaoMiao.allReadings[(MiaoMiao.allReadings.count - 6) ..< (MiaoMiao.allReadings.count - 2)].reduce(0.0) { max($0, $1.value) } : MiaoMiao.allReadings.last?.value ?? defaults[.maxRange]
            if current.value > highest {
                show = "\(current.value > 250 ? "H" : "h")⤴︎"
            } else {
                show = "\(current.value > 250 ? "H" : "h")⤵︎"
            }
            
            
        case defaults[.minRange] ..< defaults[.maxRange]:
            let mid = (defaults[.minRange] + defaults[.maxRange]) / 2
            if let state = sent[.complication] as? String, state == highRange {
                show = current.value > mid - 5 ? highRange : lowRange
            } else if let state = sent[.complication] as? String, state == lowRange {
                show = current.value < mid + 5 ? lowRange : highRange
            } else {
                show = current.value > mid ? highRange : lowRange
            }
            
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
    
    private let sharedOperationQueue = OperationQueue()
    override init() {
        super.init()
        defaults[.lastStatisticsCalculation] = nil
        trendCalculator = Calculation {
            return self.trendValue()
        }
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if let nav = window?.rootViewController as? UINavigationController, let vc = nav.viewControllers.first {
            if nav.viewControllers.count > 1 || vc.presentedViewController != nil {
                return [.portrait]
            }
        }
        return [.portrait, .landscapeRight, .landscapeLeft]
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        DependencyInjectionValues[\.databaseOpener] = MainOpener()
        DependencyInjectionValues[\.sharedDatabaseOpener] = TrendDBOpener()
        return true
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
        var trendPoints = [GlucosePoint]()
        var historyPoints = [GlucosePoint]()
        var trendDirection = Bool.random() ? -1.0 : 1.0
        
        updater = Repeater.every(5, perform: { (_) in
            var currentValue = trendPoints.first?.value ?? 120
            currentValue += trendDirection * Double.random(in: 0..<4)
            if Double.random(in: 0..<1) < 0.2 {
                trendDirection *= -1
            }
            if currentValue < 60 {
                trendDirection = 1
            } else if currentValue > 200 {
                trendDirection = -1
            }
            let gp = GlucosePoint(date: Date(), value: currentValue)
            trendPoints.insert(gp, at: 0)
            if trendPoints.count > 5 {
                let last = trendPoints.removeLast()
                historyPoints.insert(last, at: 0)
                if historyPoints.count > 15 {
                    historyPoints.removeLast()
                }
            }
            MiaoMiao.simulateData(trend: trendPoints, history: historyPoints)
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
        if clean {
            do {
                _ = try Storage.default.db.write {
                    try $0.execute(literal: "delete from meal where id not in (select mealid from entry)")
                }
                clean = false
            } catch {
                logError("Error while cleaning: \(error.localizedDescription)")
            }
        }
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
//            if url.pathExtension == "zip" {
//                DispatchQueue.global().async {
//                    _ = url.startAccessingSecurityScopedResource()
//                    do {
//                        let outputDir = try Zip.quickUnzipFile(url)
//                        try FileManager.default.removeItem(at: url)
//                        url.stopAccessingSecurityScopedResource()
//                        let path = outputDir.appendingPathComponent("read.sqlite").path
//                        if  !FileManager.default.fileExists(atPath: path) {
//                            DispatchQueue.main.async {
//                                let notification = UNMutableNotificationContent()
//                                notification.title = "Datebase not found"
//                                notification.body = "Imported zip file does not contain any database"
//                                notification.categoryIdentifier = Notification.Identifier.error
//                                let request = UNNotificationRequest(identifier: Notification.Identifier.error, content: notification, trigger: nil)
//                                UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
//                                    if let err = err {
//                                        logError("\(err)")
//                                    }
//                                })
//                            }
//                            return
//                        }
//                        let importDb = try SqliteDatabase(filepath: path)
//                        let readings = importDb.evaluate(GlucosePoint.read()) ?? []
//                        var mealCount = 0
//                        var readingCount = 0
//                        try Storage.default.db.transaction { (db)  in
//                            do {
//                                let have = db.evaluate(GlucosePoint.read()) ?? []
//                                let all = Set(have.map { $0.date })
//                                for gp in readings {
//                                    if !all.contains(gp.date) {
//                                        try db.perform(gp.insert())
//                                        readingCount += 1
//                                    }
//                                }
//                            }
//                            do {
//                                let have = db.evaluate(ManualMeasurement.read()) ?? []
//                                let all = Set(have.map { $0.date })
//                                for gp in importDb.evaluate(ManualMeasurement.read()) ?? [] {
//                                    if !all.contains(gp.date) {
//                                        try db.perform(gp.insert())
//                                        readingCount += 1
//                                    }
//                                }
//                            }
//
//                            let records = importDb.evaluate(Record.read()) ?? []
//                            let existingMeals = Set(db.evaluate(Record.read()) ?? [])
//                            var meals = [Int: Meal]()
//                            (importDb.evaluate(Meal.read()) ?? []).forEach {
//                                meals[$0.id ?? -1] = $0
//                                $0.reset()
//                            }
//                            for record in records {
//                                if !existingMeals.contains(record) {
//                                    let newRecord = Record(date: record.date, meal: record.type, bolus: record.bolus, note: record.note)
//                                    newRecord.carbs = record.carbs
//                                    if let oldMealId = record.mealId {
//                                        if let newMealId = meals[oldMealId]?.id {
//                                            newRecord.mealId = newMealId
//                                        } else if let meal = meals[oldMealId] {
//                                            try meal.save()
//                                            newRecord.mealId = meal.id
//                                        }
//                                    }
//                                    try db.perform(newRecord.insert())
//                                    mealCount += 1
//                                }
//                            }
//
//                            do {
//                                let cals = db.evaluate(Calibration.read()) ?? []
//                                let allCalibs = Set(cals.map { $0.date })
//                                let imported = importDb.evaluate(Calibration.read()) ?? []
//                                for row in imported {
//                                    if !allCalibs.contains(row.date) {
//                                        try db.perform(row.insert())
//                                    }
//                                }
//                            }
//                        }
//                        try Storage.default.db.execute("vacuum")
//                        DispatchQueue.main.async {
//                            let notification = UNMutableNotificationContent()
//                            if mealCount > 0 || readingCount > 0 {
//                                notification.title = "Imported"
//                                notification.body = "Imported \(readingCount) readings and \(mealCount) diary entries"
//                            } else {
//                                notification.title = "Nothing to Import"
//                                notification.body = "No missing records in existing database"
//                            }
//                            notification.categoryIdentifier = Notification.Identifier.imported
//                            let request = UNNotificationRequest(identifier: Notification.Identifier.imported, content: notification, trigger: nil)
//                            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
//                                if let err = err {
//                                    logError("\(err)")
//                                }
//                            })
//                        }
//                    } catch {
//                        url.stopAccessingSecurityScopedResource()
//                        DispatchQueue.main.async {
//                            let notification = UNMutableNotificationContent()
//                            notification.title = "Error Importing"
//                            notification.body = error.localizedDescription
//                            notification.categoryIdentifier = Notification.Identifier.error
//                            let request = UNNotificationRequest(identifier: Notification.Identifier.error, content: notification, trigger: nil)
//                            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
//                                if let err = err {
//                                    logError("\(err)")
//                                }
//                            })
//                        }
//                    }
//                }
//            }
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
            ctr.addRecord(meal: Entry.MealType(name: userActivity.interaction?.intent.value(forKey: "meal") as? String), units: (userActivity.interaction?.intent.value(forKey: "units") as? NSNumber)?.intValue, note: userActivity.interaction?.intent.value(forKey: "note") as? String)

        default:
            break
        }
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.badge, .sound, .banner])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let nav = window?.rootViewController as? UINavigationController, let ctr = nav.viewControllers.first as? ViewController else {
            return
        }
        switch response.notification.request.identifier {
        case Notification.Identifier.calibrate:
            ctr.calibrate()

        case Notification.Identifier.noData:
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
            .batteryLevel: MiaoMiao.batteryLevel,
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
            UserDefaults.DoubleKey.diaMinutes.key,
            UserDefaults.BoolKey.useDarkGraph.key,
            UserDefaults.IntKey.libreDays.key
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

    func sendAppState() {
        DispatchQueue.main.async {
            do {
                let state = self.filteredState(self.appState())
                try WCSession.default.updateApplicationContext(state.withStringKeys())
                log("Sent [\(state.keys.map { String(describing:$0).replacingOccurrences(of: "WoofKit.StateKey.", with: "") }.sorted().joined(separator: ", "))]")
                self.markSent(state)
            } catch {
                logError("Error sending state: \(error.localizedDescription)")
            }
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
                        for k in [StateKey.history, StateKey.trend, StateKey.batteryLevel, StateKey.sensorStart, StateKey.events] {
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

    private func showEventAlert(title: String?, body: String?, sound: UNNotificationSoundName?, level: UNNotificationInterruptionLevel) {
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
            notification.interruptionLevel = level
            defaults[.lastEventAlertTime] = Date()
            defaults[.lastEventAlertLevel] = MiaoMiao.currentGlucose?.value ?? 100
            notification.categoryIdentifier = Notification.Identifier.event
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.event])
            let request = UNNotificationRequest(identifier: Notification.Identifier.event, content: notification, trigger: nil)
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
            DispatchQueue.global().async {
                do {
                    _ = try Storage.default.trendDb.writeInTransaction { db in
                        try GlucosePoint.deleteAll(db)
                        if let trend = MiaoMiao.trend {
                            try trend.enumerated().filter { $0.offset % 3 == 0 }.forEach {
                                try $0.element.insert(db)
                            }
                        }
                        return .commit
                    }
                    DispatchQueue.main.async {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.window?.rootViewController?.present(title: "Error writing trend db", error: error)
                    }
                }
            }

            if let trend = currentTrend {
                log("\(current.value % ".02lf")\(trendSymbol(for: trend)) \(trend > 0 ? "+" : "")\(trend % ".02lf")")

                switch current.value {
                case ...defaults[.minRange] where defaults[.lastEventAlertTime] != nil:
                    if let last = defaults[.lastEventAlertTime], Date() > last + 10.m, let currentTrend = currentTrend, currentTrend < 0 {
                        showEventAlert(title: "Low & dropping", body: "Current glucose level is \(current.value.decimal(digits: 0))", sound: nil, level: .critical)
                    }
                    
                case ...defaults[.lowAlertLevel]:
                    guard current.value > defaults[.minRange] else {
                        if !didAlertEvent {
                            showEventAlert(title:  "Low Glucose", body: "Current level is \(current.value % ".0lf")", sound: UNNotificationSoundName.lowGlucose, level: .critical)
                        }
                        break
                    }
                    guard let timeToLow = estimatedTimeToLow() else {
                        break
                    }

                    if timeToLow <= defaults[.timeToLow].m && timeToLow > 0 {
                        checkIfShowingNotification(identifier: Notification.Identifier.event) {
                            let when = Date() + timeToLow
                            let hour = when.hour
                            let minLeft = timeToLow / 1.m
                            let timeMessage: String
                            if minLeft > 1 {
                                timeMessage = "\(timeToLow / 1.m % ".0f") minutes"
                            } else {
                                timeMessage = "in one minute"
                            }
                            self.showEventAlert(title:  "Trending to a Low", body: "Low predicted in \(timeMessage) at \(hour == 0 ? 12 : hour):\(when.minute % ".02ld"). Current glucose level is \(current.value.decimal(digits: 0))", sound: $0 && !self.didAlertEvent ? nil : UNNotificationSoundName.toBeLow, level: .critical)
                        }
                    } else if timeToLow < 0 || timeToLow > defaults[.timeToLow] * 2 {
                        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.event])
                        defaults[.lastEventAlertTime] = nil
                    }
                    
                case defaults[.highAlertLevel]... where !didAlertEvent && trend > 0.25:
                    showEventAlert(title: "High Glucose Reached", body: "Currantly at \(current.value % ".0lf")", sound: UNNotificationSoundName.highGlucose, level: .timeSensitive)
                    
                case defaults[.lowAlertLevel] ..< defaults[.highAlertLevel]:
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.event])
                    defaults[.lastEventAlertTime] = nil
                    
                default:
                    break
                }
            }
            if WCSession.default.activationState == .activated {
                 switch current.value {
                case defaults[.maxRange]...:
                    let highest = MiaoMiao.allReadings.count > 6 ? MiaoMiao.allReadings[(MiaoMiao.allReadings.count - 6) ..< (MiaoMiao.allReadings.count - 2)].reduce(0.0) { max($0, $1.value) } : MiaoMiao.allReadings.last?.value ?? defaults[.maxRange]
                    if current.value > highest {
                        if let last = defaults[.lastEventAlertTime], Date() > last + 10.m {
                            showEventAlert(title: "Glucose still rising", body: "Current level is \(current.value.decimal(digits: 0))", sound: nil, level: .timeSensitive)
                        }
                    }
                    
                    
                case defaults[.lowAlertLevel] ..< defaults[.maxRange]:
                    break
                    
                default:
                    break
                }
                
                if WCSession.default.isReachable {
                    sendAppState()
                } else if  WCSession.default.isComplicationEnabled && self.complicationState != (self.sent[.complication] as? String ?? "") {
                    DispatchQueue.main.async {
                        let payload: [StateKey: AnyHashable] = [.complication: self.complicationState]
                        self.markSent(payload)
                        WCSession.default.transferCurrentComplicationUserInfo(payload.withStringKeys())
                    }
                }
            }
        }
    }
    
    private func estimatedTimeToLow() -> TimeInterval? {
        guard let coef = MiaoMiao.trendline(), coef.a < -1e-6 else {
            return nil
        }
        
        return (defaults[.minRange] - coef.b) / coef.a
    }
}



extension UIApplication {
    static var theDelegate: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }
}

public func checkIfShowingNotification(identifier: String,  result: @escaping (Bool) -> Void) {
    UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: { (all) in
        for note in all {
            if note.request.identifier == identifier {
                result(true)
                return
            }
        }
        result(false)
    })
}


public extension Notification {
    enum Identifier {
        public static let noSensor = "noSensor"
        public static let event = "event"
        public static let lowBattery = "lowBattery"
        public static let noData = "noData"
        public static let calibrate = "calibrate"
        public static let newSensor = "newSensor"
        public static let imported = "imported"
        public static let error = "error"
        public static let expire = "expire"
    }
}

extension Measurement {
    var glucosePoint: GlucosePoint {
        return GlucosePoint(date: date, value: temperatureAlgorithmGlucose)
    }
    var trendPoint: GlucosePoint {
        return GlucosePoint(date: date, value: temperatureAlgorithmGlucose, isTrend: true)
    }
}

extension UNNotificationSoundName {
    public static let calibrationNeeded = UNNotificationSoundName(rawValue: "Siri_Calibration_Needed.caf")
    public static let lowGlucose = UNNotificationSoundName(rawValue: "Siri_Low_Glucose.caf")
    public static let highGlucose = UNNotificationSoundName(rawValue: "Siri_High_Glucose.caf")
    public static let missed = UNNotificationSoundName(rawValue: "Siri_Missed_Readings.caf")
    public static let lowBattery = UNNotificationSoundName(rawValue: "Siri_Transmitter_Battery_Low.caf")
    public static let toBeLow = UNNotificationSoundName(rawValue: "About_to_be_Low.caf")
    public static let sensorDie = UNNotificationSoundName("sensorDie.caf")
}
