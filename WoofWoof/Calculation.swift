//
//  Calculation.swift
//  WoofWoof
//
//  Created by Guy on 28/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import Foundation
import UIKit

private let InvalidatedNotification = Notification.Name("invalidated")

public class Calculation<Value> : NSObject {
    private var last: Value? {
        didSet {
            //            if last == nil && oldValue != nil {
            NotificationCenter.default.post(name: InvalidatedNotification, object: self)
            bindings?.forEach {
                $0(value)
            }
            //            }
        }
    }
    private var bindings: [(Value) -> Void]?

    var calculator: (() -> Value?)!
    public var value: Value {
        get {
            if let last = last {
                return last
            } else {
                last = calculator()
                return last!
            }
        }
        set {
            last = newValue
        }
    }
    public init(calculator: @escaping () -> Value) {
        self.calculator = calculator
    }
    @discardableResult public func watch<T: NSObject, V>(_ target: T, _ property: KeyPath<T, V>) -> Calculation<Value> {
        switch (target, property) {
        case (_ as UITextField, \UITextField.text):
            NotificationCenter.default.addObserver(self, selector: #selector(invalidate), name: UITextField.textDidChangeNotification, object: target)

        default:
            observe(target, keypath: property) { [weak self] (_, _) in
                self?.last = nil
            }
        }
        return self
    }
    @objc public func invalidate() {
        last = nil
    }
    @discardableResult public func watch<S>(_ target: Calculation<S>) -> Calculation<Value> {
        NotificationCenter.default.addObserver(self, selector: #selector(invalidate), name: InvalidatedNotification, object: target)
        return self
    }
    @discardableResult public func didSet(_ with: @escaping (Value) -> Void) -> Calculation<Value> {
        if bindings == nil {
            bindings = []
        }
        bindings?.append(with)
        return self
    }
    public func stop() {
        _ = value
        calculator = nil
        bindings = nil
        stopAllObservations()
    }
}
