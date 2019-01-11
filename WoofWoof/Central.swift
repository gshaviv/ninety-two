//
//  Central.swift
//  HouzzBLE
//
//  Created by Guy on 01/06/2018.
//  Copyright © 2018 Houzz. All rights reserved.
//

import Foundation
import CoreBluetooth

typealias Byte = UInt8

public class Central: NSObject {
    internal static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    internal static let transmit = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    internal static let receive = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    public static var manager = Central()
    private var centralManager: CBCentralManager!
    private var gcmDevice: CBPeripheral! {
        didSet {
            if gcmDevice == nil {
                readChannel = nil
                writeChannel = nil
            }
        }
    }
    private var readChannel: CBCharacteristic!
    private var writeChannel: CBCharacteristic!
    private var stateChangeHandlers = [(State, State) -> Void]()

    public enum State {
        case unknown
        case unavailable
        case bluetoothOff
        case bluetoothOn
        case found
        //        case error(String)
        case error
        case ready
        //        case sending(Data)
    }

    override init() {
        state = .unknown
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.tivstudio.central"])
    }

    public func onStateChange(_ h: @escaping (State, State) -> Void) {
        stateChangeHandlers.append(h)
    }

    public func start() {
    }

    public func restart() {
        guard gcmDevice != nil else {
            return
        }
        centralManager.cancelPeripheralConnection(gcmDevice)
        readChannel = nil
        writeChannel = nil
        state = .found
    }

    public var state: State {
        didSet {
            stateChangeHandlers.forEach { $0(oldValue, state) }

            switch (oldValue, state) {
            case (_, .bluetoothOn):
                gcmDevice = nil
                centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])

            case (_, .found):
                centralManager.connect(gcmDevice, options: nil)

            case (_, .ready):
                break

            case (.unknown, .unavailable):
                break

            case (_, .error):
                logError("Error")

            default:
                break
            }
        }
    }
}

extension Central: CBCentralManagerDelegate {

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let rp = peripherals.first {
            log("Restoring Central state")
            gcmDevice = rp
            rp.delegate = self
            out: for s in rp.services ?? [] {
                if s.uuid == Central.service {
                    for c in s.characteristics ?? [] {
                        switch c.uuid {
                        case Central.receive:
                            readChannel = c
                            gcmDevice.setNotifyValue(true, for: c)

                        case Central.transmit:
                            writeChannel = c

                        default:
                            break
                        }
                    }
                }
            }
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Step 1
        switch central.state {
        case .unknown, .resetting:
            state = .unknown

        case .unsupported, .unauthorized:
            state = .unavailable

        case .poweredOff:
            state = .bluetoothOff

        case .poweredOn:
            state = .bluetoothOn
            // state change will trigger transition to Step 2
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Step 2
        if gcmDevice == nil {
            log("Found \(peripheral.name ?? peripheral.identifier.uuidString)")
        }
        if gcmDevice == nil && peripheral.name?.hasPrefix("miaomiao") == true {
            gcmDevice = peripheral
            peripheral.delegate = self
            log("Connecting to \(peripheral)")
            state = .found
        }

        // state change will trigger transition to steo 3
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Step 2.1: Now start discovering services
        peripheral.discoverServices([Central.service])
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        switch state {
        case .ready:
            state = .found

        default:
            break
        }
    }
}

extension Central: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Step 2.2: Now discover characteristics of discovered services - only one service expected
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([Central.receive, Central.transmit], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([Central.receive, Central.transmit], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Step 2.3: Find our characteristic used for comm
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case Central.receive:
                readChannel = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                centralManager.stopScan()

            case Central.transmit:
                writeChannel = characteristic

            default:
                break
            }
        }

        if writeChannel != nil && readChannel != nil {
            MiaoMiao.Command.startReading()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Step 3: Now that subscribed successfully go to ready state
        if let error = error {
            logError("\(characteristic.uuid.uuidString): \(error.localizedDescription)")
            state = .error
        } else {
            state = .ready
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Receiving data from peripheral, concatinate it if needed
        if let data = characteristic.value {
            MiaoMiao.decode(data)
        }
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        // Peripheral is ready again to receive data, send if needed
    }
}

extension Central {

    func send(bytes: [Byte]) {
        let data = Data(bytes: bytes)
        send(data: data)
    }

    func send(data: Data) {
        gcmDevice.writeValue(data, for: writeChannel, type: .withoutResponse)
    }
}

extension Data {

    func array<T>() -> [T] {
        return self.withUnsafeBytes {
            [T](UnsafeBufferPointer(start: $0, count: self.count / MemoryLayout<T>.stride))
        }
    }

    var bytes: [Byte] {
        return array()
    }
}

extension Array where Element == Byte {

    func grouped(count: Int = 8, by: String = " ") -> String {
        var groups = [String]()
        var current = ""
        for (idx, byte) in enumerated() {
            current = current.appendingFormat("%02x", byte)
            if idx % count + 1 == count {
                groups.append(current)
                current = ""
            }
        }
        return groups.joined(separator: by)
    }
}
