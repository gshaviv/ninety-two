//
//  Repeater.swift
//  houzz
//
//  Created by Guy on 17/03/2018.
//

import Foundation

public class Repeater {
    private let timer: DispatchSourceTimer

    private init(timer: DispatchSourceTimer) {
        self.timer = timer
    }

    /// Create a repeating timer and start it
    ///
    /// - Parameters:
    ///   - every: repeat time in sec
    ///   - leaway: tolerance in sec, default 0
    ///   - queue: dispatch queue to call handler on, default/nil is the global queue
    ///   - perform: block to perform
    public class func every(_ every: TimeInterval, leeway: TimeInterval = 0, queue: DispatchQueue? = nil, perform: @escaping ((Repeater) -> Void)) -> Repeater {
        let timer = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(rawValue: UInt(0)), queue: queue ?? DispatchQueue.global())
        timer.schedule(deadline: DispatchTime(uptimeNanoseconds: 0), repeating: DispatchTimeInterval.milliseconds(Int(every * 1e3)), leeway: DispatchTimeInterval.nanoseconds(Int(leeway * 1e9)))
        let r = Repeater(timer: timer)
        timer.setEventHandler { [weak r] in
            guard let sr = r else {
                return
            }
            perform(sr)
        }
        timer.resume()
        return r
    }

    deinit {
        if !timer.isCancelled {
            timer.cancel()
        }
    }

    public final func cancel() {
        timer.cancel()
    }

    public final func resume() {
        timer.resume()
    }

    public final func suspend() {
        timer.suspend()
    }

    public final var isCancelled: Bool {
        return timer.isCancelled
    }
}
