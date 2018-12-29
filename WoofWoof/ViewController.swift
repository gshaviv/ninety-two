//
//  ViewController.swift
//  WoofWoof
//
//  Created by Guy on 14/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import UIKit
import Sqlable

class ViewController: UIViewController {
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var currentGlucoseLabel: UILabel!
    @IBOutlet var batteryLevelLabel: UILabel!
    @IBOutlet var sensorAgeLabel: UILabel!
    @IBOutlet var agoLabel: UILabel!
    private var updater: Repeater!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        update()
        MiaoMiao.delgate = self
        updater = Repeater.every(10, queue: DispatchQueue.main) { (_) in
            self.updateTimeAgo()
        }
    }

    func update() {
        if let last = UserDefaults.standard.last {
            if let readings = try? GlucosePoint.read().filter(GlucosePoint.date > last - 1.d).orderBy(GlucosePoint.date).run(MiaoMiao.db) {
                graphView.points = readings
                graphView.yRange.max = max(graphView.yRange.max, 180)
                graphView.yRange.min = min(graphView.yRange.min, 60)
                if !readings.isEmpty {
                    graphView.xRange.max = readings.last!.date
                    graphView.xRange.min = graphView.xRange.max - 24.h
                }
            }
        }
        if let current = MiaoMiao.currentGlucose {
            currentGlucoseLabel.text = "\(Int(round(current.value)))"
            agoLabel.text = "0 Ago"
            UIApplication.shared.applicationIconBadgeNumber = Int(round(current.value))
        } else {
            currentGlucoseLabel.text = "--"
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        if MiaoMiao.batteryLevel > 0 {
            batteryLevelLabel.text = "\(MiaoMiao.batteryLevel)%"
        } else {
            batteryLevelLabel.text = "?%"
        }
        if let age = MiaoMiao.sensorAge {
            sensorAgeLabel.text = "\(age/24/60)d:\(age / 60 % 24)h"
        } else {
            sensorAgeLabel.text = "?"
        }
    }

    private func updateTimeAgo() {
        if let current = MiaoMiao.currentGlucose {
            let time = Int(round(Date().timeIntervalSince(current.date)))
            agoLabel.text = String(format: "%ld:%02ld Ago", time / 60, time % 60)
        } else {
            agoLabel.text = ""
        }
    }
}

extension ViewController: MiaoMiaoDelegate {
    func didUpdate() {
        update()
    }


}

