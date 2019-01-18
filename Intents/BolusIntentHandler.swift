//
//  BolusIntentHandler.swift
//  SiriIntents
//
//  Created by Guy on 18/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import Intents
import WoofKit
import Sqlable

class BolusHandler: NSObject, BolusIntentHandling {
    func handle(intent: BolusIntent, completion: @escaping (BolusIntentResponse) -> Void) {
        if let u = intent.units {
            let b = Bolus(date: Date(), units: u.intValue)
            Storage.default.db.async {
                Storage.default.db.evaluate(b.insert())
                completion(BolusIntentResponse.success(units: u))
            }
            
        } else {
            completion(BolusIntentResponse(code: BolusIntentResponseCode.failureRequiringAppLaunch, userActivity: nil))
        }
    }

}
