//
//  AutoLayoutExtension.swift
//
//  Created by Guy Shaviv on 19/8/2014.
//
//

import Foundation
import UIKit

private var pendingConstraintsStack: [[NSLayoutConstraint]] = []

@discardableResult public func makeConstraints(_ identifier: String? = nil, layout: () -> Void) -> [NSLayoutConstraint] {
    assert(Thread.isMainThread)
    pendingConstraintsStack.append([])
    layout()
    let ret = pendingConstraintsStack.last!
    pendingConstraintsStack.removeLast()
    if !pendingConstraintsStack.isEmpty {
        pendingConstraintsStack[pendingConstraintsStack.count - 1] += ret
    }
    ret.forEach {
        $0.isActive = true
        $0.identifier = $0.identifier ?? identifier
    }
    return ret
}

@discardableResult public func privateConstraints(_ identifier: String? = nil, layout: () -> Void) -> [NSLayoutConstraint] {
    assert(Thread.isMainThread)
    pendingConstraintsStack.append([])
    layout()
    let ret = pendingConstraintsStack.last!
    pendingConstraintsStack.removeLast()
    ret.forEach {
        $0.isActive = true
        $0.identifier = $0.identifier ?? identifier
    }
    return ret
}

public struct LayoutItem {
    let view: AnyObject
    let attribute: NSLayoutConstraint.Attribute
    let multiplier: CGFloat
    let constant: CGFloat

    init(view: AnyObject, attribute: NSLayoutConstraint.Attribute, multiplier: CGFloat, constant: CGFloat) {
        self.constant = constant
        self.view = view
        self.attribute = attribute
        self.multiplier = multiplier
    }

    init(view: AnyObject, attribute: NSLayoutConstraint.Attribute) {
        self.view = view
        self.attribute = attribute
        multiplier = 1.0
        constant = 0.0
    }

    /// Builds a constraint by relating the item to another item.
    func relateTo(_ right: LayoutItem, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        return NSLayoutConstraint(item: view, attribute: attribute, relatedBy: relation, toItem: right.view, attribute: right.attribute, multiplier: right.multiplier, constant: right.constant)
    }

    /// Builds a constraint by relating the item to a constant value.
    func relateToConstant(_ right: CGFloat, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        return NSLayoutConstraint(item: view, attribute: attribute, relatedBy: relation, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 1.0, constant: right)
    }

    /// Equivalent to NSLayoutRelation.Equal
    func equalTo(_ right: LayoutItem) -> NSLayoutConstraint {
        return relateTo(right, relation: .equal)
    }

    /// Equivalent to NSLayoutRelation.Equal
    func equalToConstant(_ right: CGFloat) -> NSLayoutConstraint {
        return relateToConstant(right, relation: .equal)
    }

    /// Equivalent to NSLayoutRelation.GreaterThanOrEqual
    func greaterThanOrEqualTo(_ right: LayoutItem) -> NSLayoutConstraint {
        return relateTo(right, relation: .greaterThanOrEqual)
    }

    /// Equivalent to NSLayoutRelation.GreaterThanOrEqual
    func greaterThanOrEqualToConstant(_ right: CGFloat) -> NSLayoutConstraint {
        return relateToConstant(right, relation: .greaterThanOrEqual)
    }

    /// Equivalent to NSLayoutRelation.LessThanOrEqual
    func lessThanOrEqualTo(_ right: LayoutItem) -> NSLayoutConstraint {
        return relateTo(right, relation: .lessThanOrEqual)
    }

    /// Equivalent to NSLayoutRelation.LessThanOrEqual
    func lessThanOrEqualToConstant(_ right: CGFloat) -> NSLayoutConstraint {
        return relateToConstant(right, relation: .lessThanOrEqual)
    }
}

/// Multiplies the operand's multiplier by the RHS value
public func * (left: LayoutItem, right: CGFloat) -> LayoutItem {
    return LayoutItem(view: left.view, attribute: left.attribute, multiplier: left.multiplier * right, constant: left.constant)
}

/// Divides the operand's multiplier by the RHS value
public func / (left: LayoutItem, right: CGFloat) -> LayoutItem {
    return LayoutItem(view: left.view, attribute: left.attribute, multiplier: left.multiplier / right, constant: left.constant)
}

/// Adds the RHS value to the operand's constant
public func + (left: LayoutItem, right: CGFloat) -> LayoutItem {
    return LayoutItem(view: left.view, attribute: left.attribute, multiplier: left.multiplier, constant: left.constant + right)
}

/// Subtracts the RHS value from the operand's constant
public func - (left: LayoutItem, right: CGFloat) -> LayoutItem {
    return LayoutItem(view: left.view, attribute: left.attribute, multiplier: left.multiplier, constant: left.constant - right)
}

/// Equivalent to NSLayoutRelation.Equal
@discardableResult public func == (left: LayoutItem, right: LayoutItem) -> NSLayoutConstraint {
    return left.equalTo(right).activate()
}

/// Equivalent to NSLayoutRelation.Equal
@discardableResult public func == (left: LayoutItem, right: CGFloat) -> NSLayoutConstraint {
    return left.equalToConstant(right).activate()
}

/// Equivalent to NSLayoutRelation.GreaterThanOrEqual
@discardableResult public func >= (left: LayoutItem, right: LayoutItem) -> NSLayoutConstraint {
    return left.greaterThanOrEqualTo(right).activate()
}

/// Equivalent to NSLayoutRelation.GreaterThanOrEqual
@discardableResult public func >= (left: LayoutItem, right: CGFloat) -> NSLayoutConstraint {
    return left.greaterThanOrEqualToConstant(right).activate()
}

/// Equivalent to NSLayoutRelation.LessThanOrEqual
@discardableResult public func <= (left: LayoutItem, right: LayoutItem) -> NSLayoutConstraint {
    return left.lessThanOrEqualTo(right).activate()
}

/// Equivalent to NSLayoutRelation.LessThanOrEqual
@discardableResult public func <= (left: LayoutItem, right: CGFloat) -> NSLayoutConstraint {
    return left.lessThanOrEqualToConstant(right).activate()
}

precedencegroup LayoutCreation {
    lowerThan: ComparisonPrecedence
}

infix operator ~: LayoutCreation

@discardableResult public func ~ (left: NSLayoutConstraint, right: Int) -> NSLayoutConstraint {
    return left ~ UILayoutPriority(rawValue: Float(right))
}

@discardableResult public func ~ (left: NSLayoutConstraint, right: UILayoutPriority) -> NSLayoutConstraint {
    if !left.isActive {
        left.priority = right
        return left
    } else {
        guard let firstItem = left.firstItem else {
            return left
        }
        left.deactivate()
        let c = NSLayoutConstraint(item: firstItem, attribute: left.firstAttribute, relatedBy: left.relation, toItem: left.secondItem, attribute: left.secondAttribute, multiplier: left.multiplier, constant: left.constant)
        c.priority = right
        return c.activate()
    }
}

extension UIView {
    public subscript(attribute: NSLayoutConstraint.Attribute) -> LayoutItem {
        return LayoutItem(view: self, attribute: attribute)
    }
}

extension NSLayoutConstraint {
    @discardableResult final public func activate() -> NSLayoutConstraint {
        if var pendingConstraints = pendingConstraintsStack.last {
            pendingConstraintsStack.removeLast()
            pendingConstraints.append(self)
            pendingConstraintsStack.append(pendingConstraints)
        } else {
            isActive = true
        }
        return self
    }

    final public func deactivate() {
        if var pendingConstraints = pendingConstraintsStack.last {
            pendingConstraintsStack.removeLast()
            if let me = pendingConstraints.firstIndex(where: { $0 == self }) {
                pendingConstraints.remove(at: me)
            }
            pendingConstraintsStack.append(pendingConstraints)
        }
        isActive = false
    }
}

extension UILayoutGuide {
    public subscript(attribute: NSLayoutConstraint.Attribute) -> LayoutItem {
        return LayoutItem(view: self, attribute: attribute)
    }
}
