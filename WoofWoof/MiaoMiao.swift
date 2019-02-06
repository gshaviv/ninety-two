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

    private static var shortRefresh = false
    static var serial: String? {
        didSet {
            if let serial = serial, serial != defaults[.sensorSerial] {
                defaults[.additionalSlope] = 1
                defaults[.nextCalibration] = Date()
            }
        }
    }
    private static var _last24: [GlucoseReading] = [] {
        didSet {
            allReadingsCalculater.invalidate()
        }
    }
    static var last24hReadings: [GlucoseReading] {
        get {
            if _last24.isEmpty {
                let end = Date()
                if let readings = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > end - 1.d && GlucosePoint.value > 0).orderBy(GlucosePoint.date)),
                    let calibrations = Storage.default.db.evaluate(Calibration.read().filter(Calibration.date > end - 1.d).orderBy(Calibration.date)) {
                    if calibrations.isEmpty {
                        _last24 = readings
                    } else {
                        var rIdx = 0
                        var cIdx = 0
                        var together = [GlucoseReading]()
                        repeat {
                            if readings[rIdx].date < calibrations[cIdx].date {
                                together.append(readings[rIdx])
                                rIdx += 1
                            } else {
                                together.append(calibrations[cIdx])
                                cIdx += 1
                            }
                        } while rIdx < readings.count && cIdx < calibrations.count
                        if rIdx < readings.count {
                            readings[rIdx...].forEach { together.append($0) }
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
    private static var pendingReadings: [GlucosePoint] = []


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
        static let normalFrequency: [Byte] = [0xD1, 5]
        static let shortFrequency: [Byte] = [0xd1, 1]
        static let frequencyResponse: Byte = 0xd1
    }

    private static var packetData: [Byte] = []

    static func decode(_ data: Data) {
        let bytes = data.bytes
        if packetData.isEmpty {
            switch bytes[0] {
            case Code.newSensor:
                log("New sensor detected")
                Central.manager.send(bytes: Code.allowSensor)
                defaults[.additionalSlope] = 1
                DispatchQueue.main.async {
                    let notification = UNMutableNotificationContent()
                    notification.title = "New sensor detected"
                    let request = UNNotificationRequest(identifier: NotificationIdentifier.newSensor, content: notification, trigger: nil)
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationIdentifier.noData])
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

                    UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                    })
                }

            case Code.noSensor:
                logError("No Sensor detected")
                if defaults[.nextNoSensorAlert] == nil {
                    defaults[.nextNoSensorAlert] = Date() + 2.m
                }
                if !shortRefresh {
                    shortRefresh = true
                    Command.send(Code.shortFrequency)
                }
                if let d = defaults[.nextNoSensorAlert], Date() > d {
                    defaults[.nextNoSensorAlert] = Date() + 10.m
                    DispatchQueue.main.async {
                        let notification = UNMutableNotificationContent()
                        notification.title = "No Sensor Detected"
                        notification.body = "Check MiaoMiao is placed properly on top of the sensor"
                        let request = UNNotificationRequest(identifier: NotificationIdentifier.noSensor, content: notification, trigger: nil)
                        UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                            if let err = err {
                                logError("\(err)")
                            }
                        })
                    }
                } else {
                    DispatchQueue.global().after(withDelay: shortRefresh ? 30.s : 2.m ) {
                        Command.startReading()
                    }
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
                    shortRefresh = !shortRefresh
                }

            default:
                logError("Bad data")
            }
        } else {
            packetData += bytes
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationIdentifier.noData])
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
                notification.sound = UNNotificationSound(named: UNNotificationSound.missed)
                let request = UNNotificationRequest(identifier: NotificationIdentifier.noData, content: notification, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30.m, repeats: false))
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

            if let data = SensorData(uuid: Data(bytes: packetData[5 ..< 13]), bytes: Array(packetData[18 ..< 362]), derivedAlgorithmParameterSet: tempCorrection), data.hasValidCRCs {
                if data.minutesSinceStart < 30 {
                    return
                }
                sensorAge = data.minutesSinceStart.m
                serial = data.serialNumber
                let trendPoints = data.trendMeasurements().map { $0.trendPoint }
                let historyPoints = data.historyMeasurements().map { $0.glucosePoint }
                record(trend: trendPoints, history: historyPoints)
                defaults[.badDataCount] = 0
                if trendPoints[0].value > 0, let current = UIApplication.theDelegate.currentTrend, abs(current) < 0.3, let date = defaults[.nextCalibration], Date() > date {
                    if let sensorAge = sensorAge, sensorAge < 1.d {
                        defaults[.nextCalibration] = Date() + 6.h
                    } else {
                        defaults[.nextCalibration] = nil
                    }
                    showCalibrationAlert()
                }
            } else if defaults[.badDataCount] < 3 {
                defaults[.badDataCount] += 1
                Command.startReading()
            } else {
                logError("Failed to read data")
                if !shortRefresh {
                    shortRefresh = true
                    Command.send(Code.shortFrequency)
                }
            }
            packetData = []
        }
    }

    private static func removeNoSensorNotification() {
        defaults[.nextNoSensorAlert] = nil
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationIdentifier.noSensor])
        }
    }

    private static func showCalibrationAlert() {
        DispatchQueue.main.async {
            let notification = UNMutableNotificationContent()
            notification.title = "Calibration needed"
            notification.body = "Please Calibrate BG"
            notification.categoryIdentifier = "calibrate"
            let request = UNNotificationRequest(identifier: NotificationIdentifier.calibrate, content: notification, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                if let err = err {
                    logError("\(err)")
                }
            })
        }
    }

    public static var sensorAge: TimeInterval?
    public static var trend: [GlucosePoint]? {
        didSet {
            allReadingsCalculater.invalidate()
            if let current = currentGlucose {
                log("currentGlucose=\(current.value)")
                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = Int(round(current.value))
                }
                if current.value < 70 && !shortRefresh {
                    shortRefresh = true
                    Command.send(Code.shortFrequency)
                } else if current.value > 70 && shortRefresh {
                    shortRefresh = false
                    Command.send(Code.normalFrequency)
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
        var together = last24hReadings
        var toAppend = [GlucosePoint]()
        var last = Date.distantFuture
        for point in trend ?? [] {
            if let h = together.last, point.date < h.date + 2.m⁚30.s {
                break
            }
            if point.date < last {
                last = point.date - 4.m⁚30.s
                toAppend.append(point)
            }
        }
        together.append(contentsOf: toAppend.reversed())

        return together
    }

    public static var currentGlucose: GlucosePoint? {
        return trend?.first
    }

    private static func record(trend: [GlucosePoint], history: [GlucosePoint]) {
        DispatchQueue.global().async {
            var added = [GlucosePoint]()
            if let last = last24hReadings.last?.date {
                let storeInterval = 5.m
                let filteredHistory = history.filter { $0.date > last + storeInterval && $0.value > 0 }.reversed()
                added.append(contentsOf: filteredHistory)
            } else {
                Storage.default.db.async {
                    do {
                        try Storage.default.db.transaction { db in
                            try history.forEach {
                                try db.perform($0.insert())
                            }
                        }
                        history.forEach {
                            added.append($0)
                        }
                    } catch let error {
                        logError("\(error)")
                    }
                }
            }
            MiaoMiao.trend = trend.filter { $0.value > 0 }
            if !added.isEmpty {
                _last24.append(contentsOf: added)
                pendingReadings.append(contentsOf: added)
                if defaults[.writeHealthKit] {
                    HealthKitManager.shared?.write(points: added)
                }
            }
            if pendingReadings.count > 3 {
                Storage.default.db.async {
                    do {
                        try Storage.default.db.transaction { db in
                            try pendingReadings.forEach {
                                try db.perform($0.insert())
                                added.append($0)
                            }

                            pendingReadings = []
                        }
                    } catch let error {
                        logError("\(error)")
                    }
                }
            }
            if let idx = last24hReadings.firstIndex(where: { $0.date > Date() - 24.h }), idx > 0 {
                _last24 = Array(last24hReadings[idx...])
            }
            DispatchQueue.main.async {
                MiaoMiao.delegate?.forEach { $0.didUpdate(addedHistory: added) }
            }
        }
    }
}

