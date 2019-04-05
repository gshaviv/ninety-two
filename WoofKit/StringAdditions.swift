//
//  StringAdditions.swift
//  dateadditions
//
//  Created by Guy on 14/09/2016.
//  Copyright © 2016 Houzz. All rights reserved.
//

import Foundation

extension String {
    public subscript(index: Int) -> String {
        get {
            return String(self[self.index(self.startIndex, offsetBy: index)])
        }
        set {
            self[index ..< index + 1] = newValue
        }
    }

    public subscript(integerRange: Range<Int>) -> String {
        get {
            let start = index(startIndex, offsetBy: integerRange.lowerBound)
            let end = index(startIndex, offsetBy: integerRange.upperBound)
            return String(self[start ..< end])
        }
        set {
            let start = index(startIndex, offsetBy: integerRange.lowerBound)
            let end = index(startIndex, offsetBy: integerRange.upperBound)
            replaceSubrange(start ..< end, with: newValue)
        }
    }

    public subscript(from: CountablePartialRangeFrom<Int>) -> String {
        get {
            let start = index(startIndex, offsetBy: from.lowerBound)
            return String(self[start ..< endIndex])
        }
        set {
            let start = index(startIndex, offsetBy: from.lowerBound)
            replaceSubrange(start ..< endIndex, with: newValue)
        }
    }

    public subscript(upTo: PartialRangeUpTo<Int>) -> String {
        get {
            guard let upper = index(startIndex, offsetBy: upTo.upperBound, limitedBy: endIndex) else {
                return ""
            }
            return String(self[startIndex ..< upper])
        }
        set {
            guard let upper = index(startIndex, offsetBy: upTo.upperBound, limitedBy: endIndex) else {
                return
            }
            replaceSubrange(startIndex ..< upper, with: newValue)
        }
    }

    public subscript(nsrange: NSRange) -> String {
        get {
            return String(self[Range(nsrange, in: self) ?? startIndex ..< startIndex])
        }
        set {
            replaceSubrange(Range(nsrange, in: self) ?? startIndex ..< endIndex, with: newValue)
        }
    }
}

public extension NSRange {
    static let notFound: NSRange = NSRange(location: NSNotFound, length: 0)
}

extension String {
    public var nsRange: NSRange {
        return NSRange(startIndex ..< endIndex, in: self)
    }

    public var all: Range<String.Index> {
        return startIndex ..< endIndex
    }


    public func format(_ args: Any?...) -> String {
        var output = ""
        let scanner = Scan(string: self)
        enum State {
            case string, token
        }
        var state: State = .string
        var argIndex = 0
        #if DEBUG
            var allArgKeys = Set<String>()
        #endif
        let argDict: [String: Any]? = {
            guard args.count == 1, let tuple = args[0] else {
                return nil
            }
            let mirror = Mirror(reflecting: tuple)
            guard mirror.displayStyle == Mirror.DisplayStyle.tuple else {
                return nil
            }
            var d = [String: Any]()
            for (label, value) in mirror.children {
                if let label = label {
                    #if DEBUG
                        allArgKeys.insert(label)
                    #endif
                    let valueMirror = Mirror(reflecting: value)
                    if valueMirror.displayStyle == Mirror.DisplayStyle.optional {
                        if let (_, v) = valueMirror.children.first {
                            d[label] = v
                        }
                    } else {
                        d[label] = value
                    }
                }
            }
            return d
        }()

        while !scanner.isAtEnd {
            switch state {
            case .string:
                if let str = scanner.scanUpTo(string: "{") {
                    output += str
                }
                scanner.offsetScanLocation(by: 1)
                state = .token

            case .token:
                var skip = false
                if let token = scanner.scanUpTo(string: "}") {
                    if let argDict = argDict {
                        #if DEBUG
                            assert(allArgKeys.contains(token), "Error: format \"\(self)\" no argument for \(token) given")
                        #endif
                        if let arg = argDict[token] {
                            output += String(describing: arg)
                        } else {
                            skip = true
                        }
                    } else if let idx = Int(token) {
                        assert(idx <= args.count, "Error: format \"\(self)\" only \(args.count) arguments provided")
                        if idx <= args.count {
                            if let arg = args[max(idx - 1, 0)] {
                                output += String(describing: arg)
                            } else {
                                skip = true
                            }
                        }
                    } else if args.count == 1 && argIndex == 0 { // handle single named arguments
                        if let arg = args[argIndex] {
                            output += String(describing: arg)
                        } else {
                            skip = true
                        }
                        argIndex += 1
                    } else {
                        assert(false, "Error: format \"\(self)\" - Unresolved token \(token)")
                    }
                } else {
                    assert(argIndex < args.count, "Error: format \"\(self)\" only \(args.count) arguments provided")
                    if argIndex < args.count {
                        if let arg = args[argIndex] {
                            output += String(describing: arg)
                        } else {
                            skip = true
                        }
                        argIndex += 1
                    }
                }
                scanner.offsetScanLocation(by: 1)
                if skip {
                    scanner.scan(charactersIn: .whitespaces)
                }
                state = .string
            }
        }

        return output
    }
}

extension Double {
    public func formatted(with format: String) -> String {
        return String(format: format, self)
    }
}

extension CGFloat {
    public func formatted(with format: String) -> String {
        return String(format: format, self)
    }
}

extension Int {
    public func formatted(with format: String) -> String {
        return String(format: format, self)
    }
}

public extension String {
    /// Trimming string whitespace
    var trimmed: String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns string's path extension. Like NSString but Swift
    var pathExtension: String {
        if let idx = self.range(of: ".", options: .backwards, range: self.startIndex ..< self.endIndex, locale: nil)?.upperBound {
            return String(self[idx...])
        }
        return ""
    }

    /// Returns string's last path component. Like NSString but Swift
    var lastPathComponent: String {
        if let idx = self.range(of: "/", options: .backwards, range: self.startIndex ..< self.endIndex, locale: nil)?.upperBound {
            return String(self[idx...])
        }
        return self
    }

    /// Delete last path component, like NSString, but swift, return without the trailing /
    var deletingLastPathComponent: String {
        if let idx = self.range(of: "/", options: .backwards, range: self.startIndex ..< self.endIndex, locale: nil)?.lowerBound {
            return String(self[..<idx])
        }
        return ""
    }

    /// Add path components, like NSString but swift
    func appending(pathComponent str: String) -> String {
        return hasSuffix("/") || str.hasPrefix("/") ? "\(self)\(str)" : "\(self)/\(str)"
    }

    mutating func append(pathComponent str: String) {
        if !hasSuffix("/") && !str.hasPrefix("/") {
            append("/")
        }
        append(str)
    }

    /// add path extension
    func appending(pathExtension ext: String) -> String {
        return hasSuffix(".") || ext.hasPrefix(".") ? "\(self)\(ext)" : "\(self).\(ext)"
    }

    mutating func append(pathExtension ext: String) {
        if !hasSuffix(".") && !ext.hasPrefix(".") {
            append(".")
        }
        append(ext)
    }

    /// Delete path extension
    var deletingPathExtension: String {
        if let idx = self.range(of: ".", options: .backwards, range: self.startIndex ..< self.endIndex, locale: nil)?.lowerBound {
            return String(self[..<idx])
        }
        return self
    }

    /// Convenience method so optionals can be used.. e.g. myString?.toInt()
    func toInt() -> Int? {
        return Int(self)
    }
}

extension String {
    public func sentenceCase() -> String {
        return capitalizeBy(delimeter: ":", other: [".","\n"])
    }

    public func listCase() -> String {
        return capitalizeBy(delimeter: ":", other: [".",",",";"," and"," with","\n"])
    }

    private func capitalizeBy(delimeter: String, other: [String]) -> String {
        return components(separatedBy: delimeter).map {
            other.isEmpty ? $0.trimmingCharacters(in: CharacterSet.whitespaces).firstUpperCase : $0.capitalizeBy(delimeter: other[0], other: Array(other[1...]))
            }.joined(separator: "\(delimeter) ")
    }

    public var firstUpperCase: String {
        return prefix(1).uppercased() + dropFirst().lowercased()
    }
}
