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
    let measurement =  MeasurementTime()
    var dateString = ""

    override var body: AnyView {
        GlucoseFace(ago: measurement).environmentObject(appState).asAnyView
    }
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        observer = appState.$state.sink(receiveValue: {
            if $0 == .snapshot {
                self.setTitle("Ninety two")
                self.dateString = ""
            }
        })
        makeTimer()
        addMenuItem(with: UIImage(systemName: "chart.pie.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title1))!, title: "Summary", action: #selector(showSummary))
        addMenuItem(with: UIImage(systemName: "eyedropper", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title1))!, title: "Calibrate", action: #selector(calibrate))
        addMenuItem(with: UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title1))!, title: "Reload", action: #selector(reload))
        addMenuItem(with: UIImage(systemName: "playpause.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title1))!, title: "Now Playing", action: #selector(nowPlaying))
    }
    
    private func makeTimer() {
        repeater = Repeater.every(1.0, leeway: 0.001, queue: DispatchQueue.main, perform: { [weak self] sender in
            if WKExtension.shared().applicationState != .background, let last = appState.data.readings.last {
                let diff = Int(Date().timeIntervalSince(last.date))
                switch diff {
                case ..<0:
                    self?.measurement.since = ""
                    
                case 0 ..< 3600:
                    self?.measurement.since = String(format:"%ld:%02ld", diff / 60, diff % 60)
                    
                case 3600 ..< 86400:
                    self?.measurement.since = String(format:"%ld:%02ld:%02ld", diff / 3600, (diff / 60) % 60, diff % 60)
                    
                default:
                    self?.measurement.since = ">1day"
                }
                let now = Date()
                let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
                let mo = ["Jan","Feb","Mar","Apr","May","June","July","Aug","Sep","Oct","Nov","Dec"]
                let today = "\(days[now.weekDay - 1]), \(mo[now.month - 1]) \(now.day)"
                if today != self?.dateString {
                    self?.dateString = today
                    self?.setTitle(today)
                }
                
            }
        })
    }
    
    override func willActivate() {
        super.willActivate()
        dateString = ""
        makeTimer()
    }
    
    override func didAppear() {
        super.didAppear()
        dateString = ""
    }
    
    @objc func showSummary() {
        pushController(withName: "summary", context: nil)
    }
    
    @objc func calibrate() {
        presentController(withName: "calibrate", context: nil)
    }
    
    @objc func nowPlaying() {
        presentController(withName: "now", context: nil)
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


class MeasurementTime: ObservableObject {
    @Published var since: String = ""
}

struct GlucoseFaceController_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}
