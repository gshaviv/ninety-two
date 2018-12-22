//
//  Extensions.swift
//  WoofWoof
//
//  Created by Guy on 21/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation

private let hexDigits = "0123456789ABCDEF".map { $0 }


extension Data {
    public var hexString: String {
        return reduce(into: "") {
            $0.append(hexDigits[Int($1 / 16)])
            $0.append(hexDigits[Int($1 % 16)])
        }
    }
}

extension ArraySlice where Element == UInt8 {
    var uint16: UInt16 {
        return UInt16(self[0]) << 8 + UInt16(self[1])
    }
    func uint16(_ idx: Int) -> UInt16 {
        return UInt16(self[idx*2]) << 8 + UInt16(self[idx * 2 + 1])
    }
    var hexString: String {
        return reduce(into: "") {
            $0.append(hexDigits[Int($1 / 16)])
            $0.append(hexDigits[Int($1 % 16)])
        }
    }
}

extension Bundle {
    public static var documentsPath: String {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    }
}

extension Int {
    var s: TimeInterval {
        return TimeInterval(self)
    }
    var m: TimeInterval {
        return Double(self) * 60.0
    }
    var h: TimeInterval {
        return self.m * 60
    }
    var d: TimeInterval {
        return self.h * 24
    }
}


extension UserDefaults {
    static let keys = [
        DefaultKey("last", type: .date, options: [.write])
    ]
}

// MARK: - Generated accessors
extension UserDefaults {
    public var last: Date? {
        get {
            return object(forKey: "last") as? Date
        }
        set {
            set(newValue, forKey: "last")
        }
    }
}
// zcode defaults fingerprint = 73ae0c246eb2aed3f75462e0ce2c59c1
