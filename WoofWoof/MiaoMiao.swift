//
//  MiaoMiao.swift
//  WoofWoof
//
//  Created by Guy on 15/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation


class MiaoMiao {
    public static var hardware: String = ""
    public static var firmware: String = ""
    public static var batteryLevel: Int = 0 // 0 - 100

    class Command {
        static func startReading() {
            Central.manager.send(bytes: Code.startReading)
        }
    }
    class Code {
        static let newSensor: Byte = 0x32
        static let noSensor: Byte = 0x34
        static let startPacket: Byte = 0x28
        static let endPacket: Byte = 0x29
        static let startReading: [Byte] = [0xf0]
        static let allowSensor: [Byte] = [0xd3, 0x01]
    }

    private static var packetData:[Byte] = []

    static func decode(_ data: Data) {
        let bytes = data.bytes
        log("Got data: \(bytes.grouped(count: 4))")
        if packetData.isEmpty {
            switch bytes[0] {
            case Code.newSensor:
                log("New sensor detected")
                Central.manager.send(bytes: Code.allowSensor)

            case Code.noSensor:
                logError("No Sensor detected")

            case Code.startPacket:
                packetData = bytes

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

            let tempCorrection = TemperatureAlgorithmParameters(slope_slope: 0.000015623, offset_slope: 0.0017457, slope_offset: -0.0002327, offset_offset: -19.47, additionalSlope: 1, additionalOffset: 0, isValidForFooterWithReverseCRCs: 1)

            if let data = SensorData(uuid: Data(bytes: packetData[5 ..< 13]), bytes: Array(packetData[18 ..< 362]), derivedAlgorithmParameterSet: tempCorrection), data.hasValidCRCs {
                log("Trend:\n\(data.trendMeasurements().map { "\($0)" }.joined(separator: "\n"))")
                log("History:\n\(data.historyMeasurements().map { "\($0)" }.joined(separator: "\n"))")
                log("Sensor age \(data.minutesSinceStart / 60):\(data.minutesSinceStart % 60)")
                log("Sensor start date \(Date(timeIntervalSinceNow: TimeInterval(-data.minutesSinceStart * 60)))")
            } else {
                logError("Failed to read data")
            }
            packetData = []
        }
    }
}


