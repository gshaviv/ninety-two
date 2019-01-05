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

protocol MiaoMiaoDelegate {
    func didUpdate(addedHistory: [GlucosePoint])
    func didUpdateGlucose()
}

extension MiaoMiaoDelegate {
    func didUpdate(addedHistory: [GlucosePoint]) {}
    func didUpdateGlucose() {}
}

class MiaoMiao {
    public static var hardware: String = ""
    public static var firmware: String = ""
    public static var batteryLevel: Int = 0 // 0 - 100
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
                defaults[.didAlertCalibrateAfter24h] = false
                defaults[.didAlertCalibrateFirst12h] = false
                defaults[.didAlertCalibrateSecond12h] = false
            }
        }
    }
    private static var _last24: [GlucoseReading] = []
    static var last24hReadings: [GlucoseReading] {
        get {
            if _last24.isEmpty {
                let end = Date()
                if let readings = db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > end - 1.d && GlucosePoint.value > 0).orderBy(GlucosePoint.date)), // DEBUG
                    let calibrations = db.evaluate(Calibration.read().filter(Calibration.date > end - 1.d).orderBy(Calibration.date)) {
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

    static var db: SqliteDatabase = {
        let db = try! SqliteDatabase(filepath: Bundle.documentsPath + "/read.sqlite")
        db.queue = DispatchQueue(label: "db")
        try! db.createTable(GlucosePoint.self)
        try! db.createTable(Calibration.self)
        return db
    }()

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
    private static var retrying = false

    static func decode(_ data: Data) {
        let bytes = data.bytes
        if packetData.isEmpty {
            switch bytes[0] {
            case Code.newSensor:
                log("New sensor detected")
                Central.manager.send(bytes: Code.allowSensor)
                defaults[.additionalSlope] = 1

            case Code.noSensor:
                logError("No Sensor detected")
                DispatchQueue.main.async {
                    let notification = UNMutableNotificationContent()
                    notification.title = "No Sensor Detected"
                    notification.body = "Check MiaoMiao is placed properly on top of the sensor"
                    notification.categoryIdentifier = "nosensor"
                    let request = UNNotificationRequest(identifier: "noSensor", content: notification, trigger: nil)
                    UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                        if let err = err {
                            logError("\(err)")
                        }
                    })
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
        if packetData.last == Code.endPacket {
            if packetData.count < 363 {
                // bad packet
                logError("Bad packet - length = \(packetData.count)")
                packetData = []
                return
            }
            removeNoSensorNotification()

            hardware = packetData[16 ... 17].hexString
            firmware = packetData[14 ... 15].hexString
            batteryLevel = Int(packetData[13])

            let tempCorrection = TemperatureAlgorithmParameters(slope_slope: 0.000015623, offset_slope: 0.0017457, slope_offset: -0.0002327, offset_offset: -19.47, additionalSlope: defaults[.additionalSlope], additionalOffset: 0, isValidForFooterWithReverseCRCs: 1)

            if let data = SensorData(uuid: Data(bytes: packetData[5 ..< 13]), bytes: Array(packetData[18 ..< 362]), derivedAlgorithmParameterSet: tempCorrection), data.hasValidCRCs {
                serial = data.serialNumber
                sensorAge = data.minutesSinceStart
                let trendPoints = data.trendMeasurements().map { $0.glucosePoint }
                let historyPoints = data.historyMeasurements().map { $0.glucosePoint }
                record(trend: trendPoints, history: historyPoints)
                retrying = false
            } else if !retrying {
                retrying = true
                Command.startReading()
            } else {
                logError("Failed to read data")
                retrying = false
            }
            packetData = []
        }
    }

    private static func removeNoSensorNotification() {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nosensor"])
        }
    }

    private static func showCalibrationAlert() {
        DispatchQueue.main.async {
            let notification = UNMutableNotificationContent()
            notification.title = "Calibration needed"
            notification.body = "Please Calibrate BG"
            notification.categoryIdentifier = "calibrate"
            let request = UNNotificationRequest(identifier: "calibrate", content: notification, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (err) in
                if let err = err {
                    logError("\(err)")
                }
            })
        }
    }

    public static var sensorAge: Int? {
        didSet {
            guard let sensorAge = sensorAge else {
                return
            }
            switch sensorAge {
            case 0 ..< Int(12.m) where !defaults[.didAlertCalibrateFirst12h]:
                showCalibrationAlert()
                defaults[.didAlertCalibrateFirst12h] = true

            case Int(12.m) ..< Int(24.m) where !defaults[.didAlertCalibrateSecond12h]:
                showCalibrationAlert()
                defaults[.didAlertCalibrateSecond12h] = true

            case Int(24.m)... where !defaults[.didAlertCalibrateAfter24h]:
                showCalibrationAlert()
                defaults[.didAlertCalibrateAfter24h] = true

            default:
                break
            }
        }
    }
    public static var trend: [GlucosePoint]? {
        didSet {
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
                delegate?.forEach { $0.didUpdateGlucose() }
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = 0
                }
            }
        }
    }

    public static var currentGlucose: GlucosePoint? {
        return trend?.first
    }

    private static func record(trend: [GlucosePoint], history: [GlucosePoint]) {
        guard let db = try? db.createChild() else {
            return
        }
        DispatchQueue.global().async {
            var added = [GlucosePoint]()
            if let last = last24hReadings.last?.date {
                let storeInterval = 5.m
                let filteredHistory = history.filter { $0.date > last + storeInterval && $0.value > 0 }.reversed()
                added.append(contentsOf: filteredHistory)
            } else {
                do {
                    try db.beginTransaction()
                    try history.forEach {
                        try db.perform($0.insert())
                        added.append($0)
                    }
                    try db.commitTransaction()
                } catch let error {
                    logError("\(error)")
                }
            }
            MiaoMiao.trend = trend
            _last24.append(contentsOf: added)
            pendingReadings.append(contentsOf: added)
            if pendingReadings.count > 3 {
                do {
                    try db.beginTransaction()
                    try pendingReadings.forEach {
                        try db.perform($0.insert())
                        added.append($0)
                        log("Writing history \($0)")
                    }
                    try db.commitTransaction()
                    pendingReadings = []
                } catch let error {
                    logError("\(error)")
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
