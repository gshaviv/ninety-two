//
//  IntentViewController.swift
//  SiriIntentUI
//
//  Created by Guy on 12/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import IntentsUI
import SwiftUI
import WoofKit
import GRDB

// As an example, this extension's Info.plist has been configured to handle interactions for INSendMessageIntent.
// You will want to replace this or add other intents as appropriate.
// The intents whose interactions you wish to handle must be declared in the extension's Info.plist.

// You can test this example integration by saying things to Siri like:
// "Send a message using <myApp>"

class IntentViewController: UIHostingController<BGStatusView>, INUIHostedViewControlling {
    let state = WidgetState()
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: BGStatusView(entry: state, sizeClass: .medium))
    }
    
    // Prepare your view controller for the interaction to handle.
    func configureView(for parameters: Set<INParameter>, of interaction: INInteraction, interactiveBehavior: INUIInteractiveBehavior, context: INUIHostedViewContext, completion: @escaping (Bool, Set<INParameter>, CGSize) -> Void) {
        Task {
            do {
                let (points, records) = try await readData()
                let entryDate = points.last?.date ?? Date()
                await MainActor.run {
                    state.points = points
                    state.records = records
                    state.date = entryDate
                    completion(true, parameters, CGSize(width: UIScreen.main.bounds.width - 40, height: 250))
                }
            } catch {
                completion(false, parameters, CGSize.zero)
            }
        }
    }
    
    private func readData() async throws -> ([GlucosePoint], [Entry]) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let p = try Storage.default.db.read {
                        try GlucosePoint.filter(GlucosePoint.Column.date > Date() - 5.h).fetchAll($0)
                    } + Storage.default.trendDb.read {
                        try GlucosePoint.fetchAll($0)
                    }
                    Storage.default.reloadToday()
                    let records = Storage.default.lastDay.entries
                    continuation.resume(returning: (p.sorted(by: { $0.date < $1.date }), records))
                    
                } catch {
                    logError("Error reading: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
