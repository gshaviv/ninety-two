//
//  File.swift
//  WoofWoof
//
//  Created by Guy on 23/08/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation

class Predictor {
    private let lowPredictor = LowPredictionLR()
    private let highPredictor = HighPredictionLR()
    private let endPredictor = EndPredictionLR()
    
    func predict(start: Double, carbs: Double, bolus: Int, iob: Double, cob: Double) throws -> (high: Double, low: Double, end: Double) {
        let low = try lowPredictor.prediction(start: start, carbs: carbs, bolus: Double(bolus), iob: iob, cob: cob).low
        let high = try highPredictor.prediction(start: start, carbs: carbs, bolus: Double(bolus), iob: iob, cob: cob).high
        let end = try endPredictor.prediction(start: start, carbs: carbs, bolus: Double(bolus), iob: iob, cob: cob).end
        return (high,low,end)
    }
}
