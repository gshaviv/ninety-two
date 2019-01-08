//
//  InterfaceController.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import WatchKit
import Foundation

class InterfaceController: WKInterfaceController {
    @IBOutlet var glucoseLabel: WKInterfaceLabel!
    @IBOutlet var trendLabel: WKInterfaceLabel!
    @IBOutlet var agoLabel: WKInterfaceLabel!
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

    }

//    override func willActivate() {
//        super.willActivate()
//    }
//
//    override func didAppear() {
//        super.didAppear()
//        updateTime()
//        WKExtension.extensionDelegate.refresh()
//    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

    func updateTime() {
        if let last = WKExtension.extensionDelegate.readings.last {
            let minutes = Int(Date().timeIntervalSince(last.date) / 60)
            switch minutes {
            case 0:
                agoLabel.setText("Now")

            default:
                agoLabel.setText("\(minutes)m")
            }
        }
    }

    func update() {
        guard let last = WKExtension.extensionDelegate.readings.last else {
            return
        }
        glucoseLabel.setAlpha(1)
        trendLabel.setAlpha(1)
        agoLabel.setAlpha(1)
        
            glucoseLabel.setText("\(Int(round(last.value)))\(WKExtension.extensionDelegate.trendSymbol)")
        trendLabel.setText(String(format: "%@%.1lf", WKExtension.extensionDelegate.trendValue > 0 ? "+" : "", WKExtension.extensionDelegate.trendValue))
        updateTime()
    }

    func showError() {
        glucoseLabel.setAlpha(1)
        trendLabel.setAlpha(1)
        agoLabel.setAlpha(1)
        glucoseLabel.setText("?")
        trendLabel.setText("")
        agoLabel.setText("")
    }

    func blank() {
        glucoseLabel.setAlpha(0.3)
        trendLabel.setAlpha(0.3)
        agoLabel.setAlpha(0.3)

    }
}
