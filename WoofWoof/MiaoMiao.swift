//
//  MiaoMiao.swift
//  WoofWoof
//
//  Created by Guy on 15/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation
import Sqlable

protocol MiaoMiaoDelegate {
    func didUpdate()
}

class MiaoMiao {
    public static var hardware: String = ""
    public static var firmware: String = ""
    public static var batteryLevel: Int = 0 // 0 - 100
    public static var delgate: MiaoMiaoDelegate? = nil
    private static var shortRefresh = false

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

    private static var packetData:[Byte] = []
    private static var retrying = false

    static func decode(_ data: Data) {
        let bytes = data.bytes
        log("Got data: \(bytes.grouped(count: 4))")
        if packetData.isEmpty {
            switch bytes[0] {
            case Code.newSensor:
                log("New sensor detected")
                Central.manager.send(bytes: Code.allowSensor)
                UserDefaults.standard.additionalSlope = 1

            case Code.noSensor:
                logError("No Sensor detected")

            case Code.startPacket:
                packetData = bytes

            case Code.frequencyResponse:
                if bytes.count < 2  {
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
            log("Got packet length=\(packetData.count) <\(packetData.grouped())>")
            if packetData.count < 363 {
                // bad packet
                logError("Bad packet - length = \(packetData.count)")
                packetData = []
                return
            }

            hardware = packetData[16...17].hexString
            firmware = packetData[14...15].hexString
            batteryLevel = Int(packetData[13])

            log("hardware: \(hardware), firmware: \(firmware)")
            log("Battery level \(batteryLevel)%")

            let tempCorrection = TemperatureAlgorithmParameters(slope_slope: 0.000015623, offset_slope: 0.0017457, slope_offset: -0.0002327, offset_offset: -19.47, additionalSlope: UserDefaults.standard.additionalSlope, additionalOffset: 0, isValidForFooterWithReverseCRCs: 1)

            if let data = SensorData(uuid: Data(bytes: packetData[5 ..< 13]), bytes: Array(packetData[18 ..< 362]), derivedAlgorithmParameterSet: tempCorrection), data.hasValidCRCs {
                log("Trend:\n\(data.trendMeasurements().map { "\($0.glucosePoint)" }.joined(separator: "\n"))")
                log("History:\n\(data.historyMeasurements().map { "\($0.glucosePoint)" }.joined(separator: "\n"))")
                log("Sensor age \(data.minutesSinceStart / 60):\(data.minutesSinceStart % 60)")
                sensorAge = data.minutesSinceStart
                log("Sensor start date \(Date(timeIntervalSinceNow: TimeInterval(-data.minutesSinceStart * 60)))")
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

    static public var sensorAge: Int?
    static public var currentTrend: Double?

    static public var currentGlucose: GlucosePoint? {
        didSet {
            if let current = currentGlucose {
                if current.value < 60 && !shortRefresh {
                    shortRefresh = true
                    Command.send(Code.shortFrequency)
                } else if current.value > 60 && shortRefresh {
                    shortRefresh = false
                    Command.send(Code.normalFrequency)
                }
            }
        }
    }
    static private func record(trend: [GlucosePoint], history: [GlucosePoint]) {
        guard let db = try? db.createChild() else {
            return
        }
        DispatchQueue.global().async {
            if let last = UserDefaults.standard.last {
                let filteredHistory = history.filter { $0.date > last + 60 }
                let storeInterval = 5.m

                if !filteredHistory.isEmpty {
                    do {
                        try db.beginTransaction()
                        try filteredHistory.forEach {
                            try db.perform($0.insert())
                            log("Writing history \($0)")
                        }
                        try db.commitTransaction()
                        UserDefaults.standard.last = filteredHistory[0].date
                    } catch let error {
                        logError("\(error)")
                    }
                }


                var threshHold = max(history.first!.date, last) + storeInterval

                try? trend.reversed().forEach {
                    if $0.date >= threshHold {
                        try db.perform($0.insert())
                        UserDefaults.standard.last = $0.date
                        log("Wrote from trend \($0)")
                        threshHold = $0.date + storeInterval
                    }
                }
            } else {
                do {
                    try db.beginTransaction()
                    try history.forEach { try db.perform($0.insert()) }
                    try db.commitTransaction()
                    UserDefaults.standard.last = history[0].date
                } catch let error {
                    logError("\(error)")
                }
            }
            currentGlucose = trend.first
            let diffs = trend.map { $0.value }.diff()
            if diffs.count > 3 {
                let sum = diffs[0 ..< 3].reduce(0) { $1 + $0 }
                currentTrend = -sum / 3
            }
            DispatchQueue.main.async {
                MiaoMiao.delgate?.didUpdate()
            }
        }
    }
}


