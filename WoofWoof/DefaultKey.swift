//
//  DefaultKey.swift
//  HouzzFoundation
//
//  Created by Guy on 15/10/2018.
//  Copyright © 2018 Houzz. All rights reserved.
//

import Foundation

public struct DefaultKey {
    public enum DefaultType {
        case string
        case int
        case bool
        case float
        case dict
        case stringArray
        case dictArray
        case date
        case url
    }

    public struct Option: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let none = Option(rawValue: 0)
        public static let write = Option(rawValue: 1 << 1) /// generate a write setter
        public static let objc = Option(rawValue: 1 << 3) /// make accessors @objc
        public static let manual = Option(rawValue: 1 << 4) /// accessor is generated manually
    }

    /// Name of property
    public let name: String
    /// Type of property
    public let type: DefaultType
    /// Default value options
    public let options: Option
    /// If it has a default value, if none set
    public let `default`: Any?
    /// key name in api response
    public let key: String?

    public init(_ name: String, type: DefaultType, options: Option = .none, default value: Any? = nil, key: String? = nil) {
        self.name = name
        self.type = type
        self.options = options
        self.default = value
        self.key = key
    }
}
