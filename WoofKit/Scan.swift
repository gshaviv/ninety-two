//
//  Scan.swift
//  houzz
//
//  Created by Guy on 21/01/2017.
//
//

import Foundation

public final class Scan {
    let string: String
    public var scanLocation: String.Index

    public init(string: String) {
        self.string = string
        scanLocation = self.string.startIndex
    }

    public var isAtEnd: Bool {
        return scanLocation == string.endIndex
    }

    @discardableResult public func scan(string scanned: String) -> String? {
        let remain = string[scanLocation ..< string.endIndex]
        if remain.hasPrefix(scanned) {
            scanLocation = string.index(scanLocation, offsetBy: scanned.count)
            return scanned
        }
        return nil
    }

    @discardableResult public func scanUpTo(characterIn set: CharacterSet) -> String? {
        let remain = string[scanLocation ..< string.endIndex]
        let initialLocation = scanLocation
        for c in remain.unicodeScalars {
            if set.contains(c) {
                return initialLocation == scanLocation ? nil : String(string[initialLocation ..< scanLocation])
            } else {
                scanLocation = string.index(after: scanLocation)
            }
        }
        return initialLocation == scanLocation ? nil : String(string[initialLocation ..< scanLocation])
    }

    @discardableResult public func scan(charactersIn set: CharacterSet) -> String? {
        let remain = string[scanLocation ..< string.endIndex]
        let initialLocation = scanLocation
        for c in remain.unicodeScalars {
            if set.contains(c) {
                scanLocation = string.index(after: scanLocation)
            } else {
                return initialLocation == scanLocation ? nil : String(string[initialLocation ..< scanLocation])
            }
        }
        return initialLocation == scanLocation ? nil : String(string[initialLocation ..< scanLocation])
    }

    public func offsetScanLocation(by: Int) {
        if let scanLocation = string.index(scanLocation, offsetBy: by, limitedBy: string.endIndex) {
            self.scanLocation = scanLocation
        }
    }

    @discardableResult public func scanUpTo(string scanned: String) -> String? {
        let remain = string[scanLocation ..< string.endIndex]
        let initialLocation = scanLocation
        var searchLocation = scanned.startIndex
        var searchCharacter = scanned[searchLocation]
        var pendingScanLocation = scanLocation
        var inString = false
        for c in remain {
            if c == searchCharacter {
                inString = true
                pendingScanLocation = string.index(after: pendingScanLocation)
                searchLocation = scanned.index(after: searchLocation)
                if searchLocation == scanned.endIndex {
                    return initialLocation == scanLocation ? nil : String(string[initialLocation ..< scanLocation])
                }
                searchCharacter = scanned[searchLocation]
            } else {
                if inString {
                    scanLocation = string.index(after: pendingScanLocation)
                } else {
                    scanLocation = string.index(after: scanLocation)
                }
                pendingScanLocation = scanLocation
                if searchLocation != scanned.startIndex {
                    searchLocation = scanned.startIndex
                    searchCharacter = scanned[searchLocation]
                }
                if isAtEnd {
                    return initialLocation == scanLocation ? nil : String(string[initialLocation ..< scanLocation])
                }
            }
        }
        return initialLocation == scanLocation ? nil : String(string[initialLocation ..< scanLocation])
    }
}
