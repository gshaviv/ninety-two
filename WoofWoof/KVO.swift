//
//  KVO.swift
//  houzz
//
//  Created by Guy on 03/11/2017.
//

import Foundation

private var kvoKey = 0
extension NSObject {
    private struct Record: Hashable {
        fileprivate let target: UnsafeMutableRawPointer
        fileprivate let targetObject: AnyObject? // only needed in ios 10 to ensure target is not released before observation, not needed in ios 11
        let keypath: AnyKeyPath

        public func hash(into hasher: inout Hasher) {
            hasher.combine(keypath)
            hasher.combine(target)
        }

        static func ==(lhs: NSObject.Record, rhs: NSObject.Record) -> Bool {
            return lhs.target == rhs.target && lhs.keypath == rhs.keypath
        }

        init(_ t: AnyObject, path: AnyKeyPath) {
            target = Unmanaged.passUnretained(t).toOpaque()
            keypath = path
            if #available(iOS 11, *) {
                targetObject = nil
            } else {
                targetObject = t
            }
        }
    }

    private final class AllRecords {
        final var all = [Record: NSKeyValueObservation]()
        final subscript(record: Record) -> NSKeyValueObservation? {
            get {
                return all[record]
            }
            set {
                all[record] = newValue
            }
        }

        deinit {
            for (_, obs) in all {
                obs.invalidate()
            }
        }
    }

    private var active: AllRecords {
        get {
            if let all = objc_getAssociatedObject(self, &kvoKey) as? AllRecords {
                return all
            } else {
                let empty = AllRecords()
                objc_setAssociatedObject(self, &kvoKey, empty, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                return empty
            }
        }
        set {
            objc_setAssociatedObject(self, &kvoKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    public func observe<T: NSObject, V>(_ target: T?, keypath: KeyPath<T, V>, options: NSKeyValueObservingOptions = [], changeHandler: @escaping (T, NSKeyValueObservedChange<V>) -> Void) {
        guard target != nil else {
            return
        }
        var enabled = true
        let handler: (T, NSKeyValueObservedChange<V>) -> Void = { (obj, change) in
            guard enabled else {
                return
            }
            enabled = false
            changeHandler(obj,change)
            enabled = true
        }
        self.active[Record(target!, path: keypath)] = target!.observe(keypath, options: options, changeHandler: handler)
    }

    public func stopObserving<T: NSObject, V>(_ target: T?, keypath: KeyPath<T, V>) {
        guard target != nil else {
            return
        }
        self.active[Record(target!, path: keypath)] = nil
    }

    public func stopObserving<T: NSObject>(_ target: T?) {
        guard target != nil else {
            return
        }
        let p = Unmanaged.passUnretained(target!).toOpaque()
        active.all.filter { $0.key.target == p }.forEach { self.active[$0.key] = nil }
    }

    public func stopAllObservations() {
        self.active = AllRecords()
    }
}
