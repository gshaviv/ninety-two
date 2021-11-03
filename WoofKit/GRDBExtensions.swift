//
//  GRDBExtensions.swift
//  WoofKit
//
//  Created by Guy on 25/10/2021.
//  Copyright © 2021 TivStudio. All rights reserved.
//

import Foundation
import GRDB



extension DatabasePool {
    public func evaluate<FetchType: FetchRequest>(_ request: FetchType) -> [FetchType.RowDecoder]? where FetchType.RowDecoder: FetchableRecord {
        do {
            return try read {
                try request.fetchAll($0)
            }
        } catch {
            return nil
        }
    }
    
    public func perform<FetchType: FetchRequest>(_ request: FetchType) throws -> [FetchType.RowDecoder]  where FetchType.RowDecoder: FetchableRecord {
        return try read {
            try request.fetchAll($0)
        }
    }
    
    public func execute(sql literal: SQL) throws {
        try write {
            try $0.execute(literal: literal)
        }
    }
}
