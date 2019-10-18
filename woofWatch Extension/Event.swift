//
//  Event.swift
//  WoofWoof
//
//  Created by Guy on 16/10/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation

struct Event: Equatable {
    let date: Date
    let bolus: Double
    
    init(date: Double, bolus: Double) {
        self.date = Date(timeIntervalSince1970: date)
        self.bolus = bolus
    }
    
    public func insulinAction(at date:Date) -> Double {
        let t = (date - self.date) / 1.m - defaults[.delayMinutes]
        let td = defaults[.diaMinutes]
        let tp = defaults[.peakMinutes]
        if t < -defaults[.delayMinutes] || t > td  {
            return 0
        } else if t < 0 {
            return bolus
        }
        
        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let a = 2 * tau / td
        let s = 1 / (1 - a + (1 + a) * exp(-td / tau))
        let iob = 1 - s * (1 - a) * ((pow(t,2) / (tau * td * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1)
        
        return iob * bolus
    }
}

extension Array where Element == Event {
    func iob(date: Date? = nil) -> Double {
        let when = date ?? Date()
        return filter { $0.date > when - (defaults[.delayMinutes] + defaults[.diaMinutes]) * 60 }.map { $0.insulinAction(at: when) }.reduce(0, +)
    }
}
