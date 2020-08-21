//
//  MiaoMiao.swift
//  WoofWoof
//
//  Created by Guy on 15/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import UIKit
import Sqlable
import UserNotifications
import WoofKit

protocol MiaoMiaoDelegate {
    func didUpdate(addedHistory: [GlucosePoint])
    func miaomiaoError(_ error: String)
}

extension MiaoMiaoDelegate {
    func miaomiaoError(_ error: String) {}
}

class MiaoMiao {
    public static var hardware: String = ""
    public static var firmware: String = ""
    public static var batteryLevel: Int = 0 { // 0 - 100
        didSet {
            if oldValue != batteryLevel {
                log("MiaoMiao battery level = \(batteryLevel)")
            }
        }
    }
    static var delegate: [MiaoMiaoDelegate]? = nil

    public static func addDelegate(_ obj: MiaoMiaoDelegate) {
        if delegate == nil {
            delegate = []
        }
        delegate?.append(obj)
    }

    private static var shortRefresh: Bool?
    static var serial: String? {
        didSet {
            if let serial = serial, serial != defaults[.sensorSerial] {
                prepareForNewSensor()
                defaults[.sensorSerial] = serial
            }
        }
    }
    private static var _last24: [GlucoseReading] = [] {
        didSet {
            allReadingsCalculater.invalidate()
        }
    }
    static public func historyChanged() {
        _last24 = []
    }
    static var last24hReadings: [GlucoseReading] {
        get {
            if _last24.isEmpty {
                let end = Date()
                if let readings = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > end - 1.d - 30.m && GlucosePoint.value > 0).orderBy(GlucosePoint.date)),
                    let calibrations = Storage.default.db.evaluate(Calibration.read().filter(Calibration.date > end - 1.d).orderBy(Calibration.date)) {
                    if calibrations.isEmpty {
                        _last24 = readings.enumerated().compactMap {
                            if $0.offset == 0 {
                                return $0.element
                            } else if readings[$0.offset - 1].date + 3.m < $0.element.date {
                                return $0.element
                            } else {
                                return nil
                            }
                        }
                    } else {
                        var rIdx = 0
                        var cIdx = 0
                        var together = [GlucoseReading]()
                        repeat {
                            if readings[rIdx].date < calibrations[cIdx].date {
                                if together.isEmpty {
                                    together.append(readings[rIdx])
                                } else if let last = together.last?.date, readings[rIdx].date > last + 2.m {
                                    together.append(readings[rIdx])
                                }
                                rIdx += 1
                            } else {
                                together.append(calibrations[cIdx])
                                cIdx += 1
                            }
                        } while rIdx < readings.count && cIdx < calibrations.count
                        if rIdx < readings.count {
                            readings[rIdx...].forEach { together.append($0) }
                        } else if cIdx < calibrations.count {
                            calibrations[cIdx...].forEach { together.append($0) }
                        }

                        _last24 = together
                    }
                }
            }
            return _last24
        }
        set {
            _last24 = newValue
        }
    }
    private static var pendingReadings: [GlucosePoint] = [] {
        didSet {
            allReadingsCalculater.invalidate()
        }
    }


    class Command {

        static func startReading() {
            Central.manager.send(bytes: Code.startReading)
        }

        static func send(_ bytes: [Byte]) {
            Central.manager.send(bytes: bytes)
        }
    }

    class Code {
        static let newSensor: Byte = 0x32
        static let noSensor: Byte = 0x34
        static let startPacket: Byte = 0x28
        static let endPacket: Byte = 0x29
        static let startReading: [Byte] = [0xf0]
        static let allowSensor: [Byte] = [0xd3, 0x01]
        static let normalFrequency: [Byte] = [0xD1, 3]
        static let shortFrequency: [Byte] = [0xd1, 1]
        static let startupFrequency: [Byte] = [0xd1, 5]
        static let frequencyResponse: Byte = 0xd1
    }

    private static var packetData: [Byte] = []
    public static var sensorState: SensorState = .unknown

    private static func prepareForNewSensor() {
        if !pendingReadings.isEmpty {
            Storage.default.db.async {
                do {
                    try Storage.default.db.transaction { db in
                        try pendingReadings.forEach {
                            try db.perform($0.insert())
                        }

                        pendingReadings = []
                    }
                } catch let error {
                    logError("\(error)")
                }
            }
        }
        defaults[.additionalSlope] = 1
        defaults[.nextCalibration] = Date() + 1.h
        defaults[.sensorBegin] = nil
    }

    static func decode(_ data: Data) {
        let bytes = data.bytes
        if packetData.isEmpty {
            switch bytes[0] {
            case Code.newSensor:
                log("New sensor detected")
                Command.send(Code.allowSensor)
                prepareForNewSensor()
                DispatchQueue.main.async {
                    let notification = UNMutableNotificationContent()
                    notification.title = "New sensor detected"
                    notification.body = "Activate sensor using original Freestyle reader"
                    let request = UNNotificationRequest(identifier: Notification.Identifier.newSensor, content: notification, trigger: nil)
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.noData])
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

                    UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                    })
                }

            case Code.noSensor:
                logError("No Sensor detected")
                if defaults[.nextNoSensorAlert] == nil {
                    defaults[.nextNoSensorAlert] = Date() + 2.m
                }
                if let r = shortRefresh, r == false {
                    shortRefresh = true
                    Command.send(Code.shortFrequency)
                }
                if let d = defaults[.nextNoSensorAlert], Date() > d && UIApplication.shared.applicationState == .background {
                    defaults[.nextNoSensorAlert] = Date() + 10.m
                    DispatchQueue.main.async {
                        let notification = UNMutableNotificationContent()
                        notification.title = "Sensor not detected"
                        notification.body = "Check MiaoMiao is placed properly on top of the sensor"
                        let request = UNNotificationRequest(identifier: Notification.Identifier.noSensor, content: notification, trigger: nil)
                        UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                            if let err = err {
                                logError("\(err)")
                            }
                        })
                    }
                } else {
                    DispatchQueue.global().after(withDelay: 30.s) {
                        Command.startReading()
                    }
                }
                DispatchQueue.main.async {
                    MiaoMiao.delegate?.forEach { $0.miaomiaoError("Sensor not detected") }
                }

            case Code.startPacket:
                packetData = bytes

            case Code.frequencyResponse:
                if bytes.count < 2 {
                    break
                }
                switch bytes[1] {
                case 0x01:
                    log("Success changing frequency")

                default:
                    logError("Failed to change frequency")
                    if let sr = shortRefresh {
                        shortRefresh = !sr
                    }
                }

            default:
                logError("Bad data")
            }
        } else {
            packetData += bytes
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.noData])
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        if packetData.last == Code.endPacket {
            if packetData.count < 363 {
                // bad packet
                logError("Bad packet - length = \(packetData.count)")
                packetData = []
                return
            }
            removeNoSensorNotification()

            DispatchQueue.main.async {
                let notification = UNMutableNotificationContent()
                notification.title = "No Transmitter Detected"
                notification.body = "Lost connection to the MiaoMiao transmitter"
                notification.sound = UNNotificationSound(named: UNNotificationSoundName.missed)
                let request = UNNotificationRequest(identifier: Notification.Identifier.noData, content: notification, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30.m, repeats: false))
                UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                    if let err = err {
                        logError("\(err)")
                    }
                })
            }

            hardware = packetData[16 ... 17].hexString
            firmware = packetData[14 ... 15].hexString
            batteryLevel = Int(packetData[13])

            let tempCorrection = TemperatureAlgorithmParameters(slope_slope: 0.000015623, offset_slope: 0.0017457, slope_offset: -0.0002327, offset_offset: -19.47, additionalSlope: defaults[.additionalSlope], additionalOffset: 0, isValidForFooterWithReverseCRCs: 1)

            if let data = SensorData(uuid: Data(packetData[5 ..< 13]), bytes: Array(packetData[18 ..< 362]), derivedAlgorithmParameterSet: tempCorrection), data.hasValidCRCs {
                defaults[.badDataCount] = 0
                serial = data.serialNumber
                sensorAge = data.minutesSinceStart.m
                sensorState = data.state
                switch data.state {
                case .notYetStarted:
                    DispatchQueue.main.async {
                        let notification = UNMutableNotificationContent()
                        notification.title = "Sensor not yet activated"
                        notification.body = "Activate sensor using original Freestyle reader"
                        let request = UNNotificationRequest(identifier: Notification.Identifier.newSensor, content: notification, trigger: nil)
                        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.noData])
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

                        UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                        })
                    }

                case .starting:
                    DispatchQueue.main.async {
                        let minutes = Int((self.sensorAge ?? 0) / 60)
                        log("New sensor: \(minutes)m old")
                        MiaoMiao.delegate?.forEach { $0.miaomiaoError("Sensor starting up: \(minutes)m") }
                    }

                case .ready:
                    if let age = sensorAge, age < 30.m {
                        DispatchQueue.main.async {
                            let minutes = Int((self.sensorAge ?? 0) / 60)
                            log("New sensor: \(minutes)m old")
                            MiaoMiao.delegate?.forEach { $0.miaomiaoError("Sensor starting up: \(minutes)m") }
                        }
                    } else {
                        let trendPoints = data.trendMeasurements().map { $0.trendPoint }
                        let historyPoints = data.historyMeasurements().map { $0.glucosePoint }
                        record(trend: trendPoints, history: historyPoints)
                        if trendPoints[0].value > 80 && trendPoints[0].value < 160, let current = UIApplication.theDelegate.currentTrend, current < 0 && current > -0.2, let line = MiaoMiao.trendline(), abs(line.a) < 0.006 {
                            if let date = defaults[.nextCalibration], Date() > date  {
                                checkIfShowingNotification(identifier: Notification.Identifier.calibrate) {
                                    if !$0 {
                                        showCalibrationAlert()
                                    }
                                }
                            }
                        } else {
                            checkIfShowingNotification(identifier: Notification.Identifier.calibrate) {
                                if $0 {
                                    defaults[.nextCalibration] = Date() + 15.m
                                }
                                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.calibrate])
                            }
                        }
                    }

                case .expired:
                    let trendPoints = data.trendMeasurements().map { $0.trendPoint }
                    let historyPoints = data.historyMeasurements().map { $0.glucosePoint }
                    record(trend: trendPoints, history: historyPoints)
                    log("sensor expired")


                case .failure:
                    if let sr = shortRefresh, !sr {
                        shortRefresh = true
                        Command.send(Code.shortFrequency)
                    }
                    DispatchQueue.main.async {
                        MiaoMiao.delegate?.forEach { $0.miaomiaoError("Sensor failed") }
                    }
                case .shutdown:
                    DispatchQueue.main.async {
                        log("sensor shutdown")
                        MiaoMiao.delegate?.forEach { $0.miaomiaoError("Sensor shutdown") }
                    }

                case .unknown:
                    break
                }
            } else if defaults[.badDataCount] < 3 {
                defaults[.badDataCount] += 1
                Command.startReading()
                DispatchQueue.main.async {
                    MiaoMiao.delegate?.forEach { $0.didUpdate(addedHistory: []) }
                }
            } else {
                logError("Failed to read data")
                if let sr = shortRefresh, !sr {
                    shortRefresh = true
                    Command.send(Code.shortFrequency)
                }
                DispatchQueue.main.async {
                    MiaoMiao.delegate?.forEach { $0.miaomiaoError("Failed to read data") }
                }
            }
            packetData = []
        }
    }

    private static func removeNoSensorNotification() {
        defaults[.nextNoSensorAlert] = nil
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.noSensor])
        }
    }

    private static func showCalibrationAlert() {
        DispatchQueue.main.async {
            let notification = UNMutableNotificationContent()
            notification.title = "Calibration needed"
            notification.body = "Please Calibrate BG Now"
            notification.categoryIdentifier = "calibrate"
            notification.sound = UNNotificationSound(named: UNNotificationSoundName.calibrationNeeded)
            let request = UNNotificationRequest(identifier: Notification.Identifier.calibrate, content: notification, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                if let err = err {
                    logError("\(err)")
                }
            })
        }
    }

    public static var sensorAge: TimeInterval? {
        get {
            if let start = defaults[.sensorBegin] {
                return Date() - start
            }
            return nil
        }
        set {
            if let newValue = newValue {
                if defaults[.sensorBegin] == nil {
                    defaults[.sensorBegin] = Date() - newValue
                    let xDate = Date() - newValue + 14.d + 10.h
                    DispatchQueue.main.async {
                        let notification = UNMutableNotificationContent()
                        notification.title = "Sensor about to fail"
                        notification.body = "Sensor is over 10 hours beyond expiration"
                        notification.sound = UNNotificationSound(named: .sensorDie)
                        let request = UNNotificationRequest(identifier: Notification.Identifier.expire, content: notification, trigger: UNCalendarNotificationTrigger(dateMatching: xDate.components, repeats: false))
                        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.expire])
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                        
                        UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                        })
                    }
                }
            } else {
                defaults[.sensorBegin] = nil
            }
        }
    }
    private static var wrongFrequencyCount = 0
    public static var trend: [GlucosePoint]? {
        didSet {
            allReadingsCalculater.invalidate()
            if let current = currentGlucose {
                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = Int(round(current.value))
                }
                if current.value < 70 {
                    if shortRefresh == nil || !shortRefresh! {
                        shortRefresh = true
                        Command.send(Code.shortFrequency)
                    } else if let last = oldValue?.first?.date, abs(abs(last - Date()) - 1.m) > 30.s {
                        wrongFrequencyCount += 1
                        if wrongFrequencyCount > 2 {
                            Command.send(Code.shortFrequency)
                            wrongFrequencyCount = 0
                        }
                    } else {
                        wrongFrequencyCount = 0
                    }
                } else if current.value > 70 {
                    if shortRefresh == nil || shortRefresh! {
                        shortRefresh = false
                        Command.send(Code.normalFrequency)
                    } else if let last = oldValue?.first?.date, abs(abs(last - Date()) - 3.m) > 30.s {
                        wrongFrequencyCount += 1
                        if wrongFrequencyCount > 2 {
                            Command.send(Code.normalFrequency)
                            wrongFrequencyCount = 0
                        }
                    } else {
                        wrongFrequencyCount = 0
                    }
                }
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = 0
                }
            }
        }
    }
    public static var allReadings: [GlucoseReading] {
        return allReadingsCalculater.value
    }
    private static var lastDate: Date = Date.distantPast
    private static var allReadingsCalculater = Calculation { () -> [GlucoseReading] in
        var toAppend = [GlucosePoint]()
        var last = Date.distantFuture
        for point in trend ?? [] {
             if point.date < last {
                last = point.date - (2⁚30).s
                toAppend.append(point)
            }
        }

        if toAppend.isEmpty {
            return last24hReadings
        }

        return last24hReadings.filter { $0.date < toAppend.last!.date - 2.m } + toAppend.reversed()
    }

    public static var currentGlucose: GlucosePoint? {
        return trend?.first
    }
    
    public static func addCalibration(value bg: Double) {
        if let current = currentGlucose {
            do {
                let c = Calibration(date: Date(), value: bg)
                try Storage.default.db.perform(c.insert())
                let factor = bg / current.value
                defaults[.additionalSlope] *= factor
                if let age = MiaoMiao.sensorAge {
                    switch (abs(factor - 1) < 0.1, age > 1.d) {
                    case (true, false):
                        defaults[.nextCalibration] = Date() + 6.h

                    case (true, true):
                        defaults[.nextCalibration] = nil

                    case (false, _):
                        defaults[.nextCalibration] = Date() + 3.h
                    }
                    
                }
                UIApplication.shared.applicationIconBadgeNumber = Int(round(bg))
                last24hReadings.append(c)
                defaults[.sensorSerial] = serial
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notification.Identifier.calibrate])
            } catch _ {}
        }
    }
    
    public static func flushToDatabase() {
        if pendingReadings.count > 3 {
            Storage.default.db.async {
                do {
                    try Storage.default.db.transaction { db in
                        var lastDate = db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > Date() - 8.h).orderBy(GlucosePoint.date))?.last?.date
                        try pendingReadings.forEach {
                            if let lastDate = lastDate {
                                if $0.date - 3.m > lastDate {
                                    try db.perform($0.insert())
                                }
                            } else {
                                try db.perform($0.insert())
                            }
                            lastDate = $0.date
                        }
                        
                        pendingReadings = []
                    }
                } catch let error {
                    logError("\(error)")
                }
            }
        }
    }
    
    public static func trendline() -> (a: Double,b: Double)? {
        guard let trend = trend else {
            return nil
        }
        let n = Double(trend.count)
        guard n > 2 else {
            return nil
        }
        let s = trend.reduce((x: 0.0, x2: 0.0, y: 0.0, xy: 0.0)) {
            let x = $1.date - trend[0].date
            let y = $1.value
            return $0 + (x, x * x, y, x * y)
        }
        let denom = n * s.x2 - s.x * s.x
        guard abs(denom) > 1e-6 else {
            return nil
        }
        let a = (n * s.xy - s.x * s.y) / denom
        let b = (s.y * s.x2 - s.x * s.xy) / denom
        
        return (a: a, b: b)
    }

    private static func record(trend: [GlucosePoint], history: [GlucosePoint]) {
        DispatchQueue.global().async {
            var added = [GlucosePoint]()
            if let last = last24hReadings.last?.date {
                let storeInterval = 3.m
                let filteredHistory = history.filter {$0.date < (defaults[.sensorBegin] ?? Date.distantFuture) + 14.d + 12.h && $0.date > last + storeInterval && $0.value > 0 && $0.date > (defaults[.sensorBegin] ?? Date.distantPast) + 50.m }.reversed()
                added.append(contentsOf: filteredHistory)
            } else {
                pendingReadings.append(contentsOf: history.filter { $0.value > 0 && $0.date > (defaults[.sensorBegin] ?? Date.distantPast) + 50.m }.reversed())
            }
            MiaoMiao.trend = trend.filter { $0.value > 0 }
            if !added.isEmpty {
                addPoints(added)
                pendingReadings.append(contentsOf: added)
                if defaults[.writeHealthKit] {
                    HealthKitManager.shared?.findLast {
                        let date = $0 ?? Date.distantPast
                        HealthKitManager.shared?.write(points: added.filter { $0.date > date })
                    }
                }
            }
            flushToDatabase()
            
            if let idx = last24hReadings.firstIndex(where: { $0.date > Date() - 24.h - 30.m }), idx > 0 {
                _last24 = Array(last24hReadings[idx...])
            }
            DispatchQueue.main.async {
                MiaoMiao.delegate?.forEach { $0.didUpdate(addedHistory: added) }
            }
        }
    }

    static private func addPoints(_ data: [GlucoseReading]) {
        for point in data {
            if point.date - 3.m > (_last24.last?.date ?? Date.distantFuture) {
                _last24.append(point)
            }
        }
    }

    static public func unloadMemory() {
        _last24 = []
    }
}

private func + (lhs: (x: Double, x2: Double, y: Double, xy: Double), rhs: (x: Double, x2: Double, y: Double, xy: Double))  -> (x: Double, x2: Double, y: Double, xy: Double) {
    (x: lhs.x + rhs.x, x2: lhs.x2 + rhs.x2, y: lhs.y + rhs.y, xy: lhs.xy + rhs.xy)
}
