//
//  Central.swift
//  HouzzBLE
//
//  Created by Guy on 01/06/2018.
//  Copyright © 2018 Houzz. All rights reserved.
//

import Foundation
import CoreBluetooth
import UIKit
import WoofKit

typealias Byte = UInt8

public class Central: NSObject {
    internal static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    internal static let transmit = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    internal static let receive = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    private var bgTask: UIBackgroundTaskIdentifier?

    public static var manager = Central()
    private var centralManager: CBCentralManager!
    private var gcmDevice: CBPeripheral? {
        didSet {
            if gcmDevice == nil {
                readChannel = nil
                writeChannel = nil
            } else {
                centralManager.stopScan()
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
        if bgTask == nil && UIApplication.shared.applicationState == .background {
            bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        }
        if let gcmDevice = gcmDevice  {
            centralManager.cancelPeripheralConnection(gcmDevice)
        }
        gcmDevice = nil
        readChannel = nil
        writeChannel = nil
        state = .bluetoothOn
    }

    public var state: State {
        didSet {
            stateChangeHandlers.forEach { $0(oldValue, state) }

            switch (oldValue, state) {
            case (_, .bluetoothOn):
                gcmDevice = nil
                centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
                if bgTask == nil && UIApplication.shared.applicationState == .background {
                    bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }

            case (_, .found):
                if let gcmDevice = gcmDevice {
                    if bgTask == nil {
                        bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                    }
                    centralManager.connect(gcmDevice, options: nil)
                }

            case (_, .ready):
                if let task = bgTask {
                    UIApplication.shared.endBackgroundTask(task)
                    bgTask = nil
                }
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
            self.onStateChange { (_, newState) in
                if newState == .bluetoothOn {
                    DispatchQueue.main.async {
                        _ = self.stateChangeHandlers.removeLast()
                        self.gcmDevice = rp
                        rp.delegate = self
                        self.state = .found
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

        @unknown default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Step 2
        if peripheral.name?.hasPrefix("miaomiao") == true {
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
        let data = Data(bytes)
        send(data: data)
    }

    func send(data: Data) {
        if let writeChannel = writeChannel {
        gcmDevice?.writeValue(data, for: writeChannel, type: .withoutResponse)
        }
    }
}

extension Data {

    func array<T>() -> [T] {
        return self.withUnsafeBytes {
            guard let addr = $0.baseAddress?.assumingMemoryBound(to: T.self)  else { return [] }
            return [T](UnsafeBufferPointer(start: addr, count: self.count / MemoryLayout<T>.stride))
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
