//
//  MiaoMiao.swift
//  WoofWoof
//
//  Created by Guy on 15/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import UIKit
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
            if packetData.count < 363 {
                // bad packet
                logError("Bad packet - length = \(packetData.count)")
                packetData = []
                return
            }

            hardware = packetData[16...17].hexString
            firmware = packetData[14...15].hexString
            batteryLevel = Int(packetData[13])

            let tempCorrection = TemperatureAlgorithmParameters(slope_slope: 0.000015623, offset_slope: 0.0017457, slope_offset: -0.0002327, offset_offset: -19.47, additionalSlope: UserDefaults.standard.additionalSlope, additionalOffset: 0, isValidForFooterWithReverseCRCs: 1)

            if let data = SensorData(uuid: Data(bytes: packetData[5 ..< 13]), bytes: Array(packetData[18 ..< 362]), derivedAlgorithmParameterSet: tempCorrection), data.hasValidCRCs {
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

    static public var sensorAge: Int?
    static public var trend: [GlucosePoint]?

    static public var currentGlucose: GlucosePoint? {
        didSet {
            if let current = currentGlucose {
                log("currentGlucose=\(current.value)")
                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = Int(round(current.value))
                }
                if current.value < 60 && !shortRefresh {
                    shortRefresh = true
                    Command.send(Code.shortFrequency)
                } else if current.value > 60 && shortRefresh {
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
    static private func record(trend: [GlucosePoint], history: [GlucosePoint]) {
        guard let db = try? db.createChild() else {
            return
        }
        DispatchQueue.global().async {
            if let last = UserDefaults.standard.last {
                let storeInterval = 5.m
                let filteredHistory = history.filter { $0.date > last + storeInterval }

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
            MiaoMiao.trend = trend
            DispatchQueue.main.async {
                MiaoMiao.delgate?.didUpdate()
            }
        }
    }
}


