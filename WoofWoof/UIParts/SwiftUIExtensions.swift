//
//  SwiftUIExtensions.swift
//  SwiftUIComponents
//
//  Created by Guy on 23/09/2019.
//  Copyright © 2019 Guy. All rights reserved.
//

import Foundation
import SwiftUI

extension String: Identifiable {
    public typealias ID = Int
    public var id: ID {
        return hashValue
    }
}

extension Int: Identifiable {
    public typealias ID = Int
    public var id: ID {
        return self
    }
}

@available(iOS 13,*)
extension Array: Identifiable where Element: Identifiable {
    public typealias ID = Int
    public var id: Int {
        var hasher = Hasher()
        forEach { hasher.combine($0.id) }
        return hasher.finalize()
    }
}

extension View {
    /// Returns a type-erased version of the view.
    public var asAnyView: AnyView {
        AnyView(self)
    }
    
    public func width(_ w: CGFloat) -> some View {
        self.frame(width: w)
    }
    
    public func height(_ h: CGFloat) -> some View {
        self.frame(height: h)
    }
}

//extension Array where Element: Numeric, Element: Comparable {
//    public func sum() -> Element {
//        return reduce(0, +)
//    }
//    
//    public func biggest() -> Element {
//        return reduce(self[0]) { Swift.max($0, $1) }
//    }
//    
//    public func smallest() -> Element {
//        return reduce(self[0]) { Swift.min($0, $1) }
//    }
//}
