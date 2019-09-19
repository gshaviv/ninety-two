//
//  GlucoseFaceController.swift
//  woofWatch Extension
//
//  Created by Guy on 19/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

class CurrentTime: ObservableObject {
    @Published var value = Date()
}

class GlucoseFaceController: WKHostingController<GlucoseFace> {
    let currentTime = CurrentTime()
    var started = false
    var repeater: Repeater?
    override var body: GlucoseFace {
        return GlucoseFace(state: appState, currentTime: currentTime)
    }
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: WKExtension.didEnterBackgroundNotification, object: nil)
        makeRepeater()
    }
    
    func makeRepeater() {
        if repeater == nil {
        self.currentTime.value = Date()
        }
        repeater?.cancel()
        repeater = Repeater.every(1.0, leeway: 0.001, queue: DispatchQueue.main, perform: { sender in
            if WKExtension.shared().applicationState != .background {
                self.currentTime.value = Date()
            } else {
                sender.cancel()
            }
        })
    }
    
    @objc private func didEnterForeground() {
        makeRepeater()
    }
    
    override func willActivate() {
        super.willActivate()
        makeRepeater()
    }
}
