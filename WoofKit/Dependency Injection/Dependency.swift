//
//  Inject.swift
//  Assignment
//
//  Created by Guy on 14/10/2021.
//

import Foundation

@propertyWrapper
public struct Dependency<T> {
    private let keyPath: WritableKeyPath<DependencyInjectionValues, T>
    public var wrappedValue: T {
        get { DependencyInjectionValues[keyPath] }
        set { DependencyInjectionValues[keyPath] = newValue }
    }
    
    public init(_ keyPath: WritableKeyPath<DependencyInjectionValues, T>) {
        self.keyPath = keyPath
    }
}


public protocol DependencyInjectionKey {
    
    /// The associated type representing the type of the dependency injection key's value.
    associatedtype Value
    
    /// The default value for the dependency injection key.
    static var currentValue: Self.Value { get set }
}
