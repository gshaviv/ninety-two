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
import WatchConnectivity

class GlucoseFaceController: WKHostingController<AnyView> {
    var observer: AnyCancellable?
    var started = false
    var repeater: Repeater?

    override var body: AnyView {
        GlucoseFace().environmentObject(appState).asAnyView
    }
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        observer = appState.$state.sink(receiveValue: {
            if $0 == .snapshot {
                self.setTitle("Ninety two")
            }
        })
        makeTimer()
        addMenuItem(with: UIImage(systemName: "chart.pie.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title1))!, title: "Summary", action: #selector(showSummary))
        addMenuItem(with: UIImage(systemName: "eyedropper", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title1))!, title: "Calibrate", action: #selector(calibrate))
         addMenuItem(with: UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title1))!, title: "Reload", action: #selector(reload))
    }
    
    private func makeTimer() {
        repeater = Repeater.every(1.0, leeway: 0.001, queue: DispatchQueue.main, perform: { [weak self] sender in
            if WKExtension.shared().applicationState != .background, let last = appState.data.readings.last {
                let diff = Int(Date().timeIntervalSince(last.date))
                switch diff {
                case ..<0:
                    self?.setTitle("Ninety Two")
                    
                case 0 ..< 3600:
                    self?.setTitle(String(format:"%ld:%02ld", diff / 60, diff % 60))
                    
                case 3600 ..< 86400:
                    self?.setTitle(String(format:"%ld:%02ld:%02ld", diff / 3600, (diff / 60) % 60, diff % 60))
                    
                default:
                    self?.setTitle(">1day")
                }
                
            }
        })
    }
    
    override func willActivate() {
        super.willActivate()
        makeTimer()
    }
    
    
    @objc func showSummary() {
        pushController(withName: "summary", context: nil)
    }
    
    @objc func calibrate() {
        presentController(withName: "calibrate", context: nil)
    }
    
    @objc func reload() {
        appState.state = .sending
        WCSession.default.sendMessage(["op":["fullState","defaults","summary"]], replyHandler: { (info) in
            DispatchQueue.main.async {
                ExtensionDelegate.replyHandler(info)
            }
        }) { (_) in
            appState.state = .error
        }
    }
}
