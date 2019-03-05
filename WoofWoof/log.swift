//
//  log.swift
//  WoofWoof
//
//  Created by Guy on 14/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation
import os

private let general = OSLog(subsystem: "92", category: "🔷")
private let error = OSLog(subsystem: "92", category: "❌")

public func log(_ msg: String) {
    os_log(.default, log: general, "%{public}@", msg)
}

public func logError(_ msg: String) {
    os_log(.error, log: error, "%{public}@", msg)
}
