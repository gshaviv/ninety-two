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

    override func viewDidLoad() {
        super.viewDidLoad()
        if let last = UserDefaults.standard.last {
            if let readings = try? GlocusePoint.read().filter(GlocusePoint.date > last - 1.d).orderBy(GlocusePoint.date).run(MiaoMiao.db) {
                graphView.points = readings
                graphView.yRange.max = max(graphView.yRange.max, 200)
                graphView.yRange.min = min(graphView.yRange.min, 60)
                if !readings.isEmpty {
                    graphView.xRange.max = readings.last!.date
                    graphView.xRange.min = graphView.xRange.max - 24.h
                }
            }
        }
    }


}

