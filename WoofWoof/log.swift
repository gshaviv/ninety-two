//
//  log.swift
//  WoofWoof
//
//  Created by Guy on 14/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation
import os

public func log(_ msg: String) {
    os_log(.default, "%{public}@", msg)
}

public func logError(_ msg: String) {
    os_log(.error, "%{public}@", msg)
}
