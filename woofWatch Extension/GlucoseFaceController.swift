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

class GlucoseFaceController: WKHostingController<AnyView> {
    let currentTime = CurrentTime()
    var started = false
    var repeater: Repeater?
    override var body: AnyView {
        GlucoseFace(state: appState).environmentObject(currentTime).asAnyView
    }
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: WKExtension.didEnterBackgroundNotification, object: nil)
        makeRepeater()
    }
    
    func makeRepeater() {
        guard repeater == nil else { return }
        self.currentTime.value = Date()
        repeater = Repeater.every(1.0, leeway: 0.001, queue: DispatchQueue.main, perform: { [weak self] sender in
            if WKExtension.shared().applicationState != .background {
                self?.currentTime.value = Date()
            } else {
                sender.cancel()
                self?.repeater = nil
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
