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
