//
//  Providers.swift
//  Assignment
//
//  Created by Guy on 14/10/2021.
//

import Foundation

public struct DependencyInjectionValues {
    
    /// This is only used as an accessor to the computed properties.
    private static var current = DependencyInjectionValues()
    
    /// A static subscript for updating the `currentValue` of `InjectionKey` instances.
    static public subscript<K>(key: K.Type) -> K.Value where K : DependencyInjectionKey {
        get { key.currentValue }
        set { key.currentValue = newValue }
    }
    
    /// A static subscript accessor for updating and references dependencies directly.
    static public subscript<T>(_ keyPath: WritableKeyPath<DependencyInjectionValues, T>) -> T {
        get { current[keyPath: keyPath] }
        set { current[keyPath: keyPath] = newValue }
    }
}
