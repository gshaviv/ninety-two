//
//  TodayViewController.swift
//  woofWidget
//
//  Created by Guy on 10/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import NotificationCenter
import GRDB
import WoofKit
import Intents
import Combine

class TodayViewController: UIViewController {
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var agoLabel: UILabel?
    @IBOutlet var trendLabel: UILabel?
    @IBOutlet var glucoseLabel: UILabel?
    @IBOutlet var iobLabel: UILabel?
    private var bag = [AnyCancellable]()
    private var points: [GlucosePoint] = [] {
        didSet {
            if let current = points.first {
                updateTime()
                graphView.points = points
                graphView.yRange.max = ceil(graphView.yRange.max / 10) * 10
                graphView.yRange.min = floor(graphView.yRange.min / 5) * 5
                if graphView.yRange.max - graphView.yRange.min < 40 {
                    let mid = (graphView.yRange.max + graphView.yRange.min) / 2
                    graphView.yRange = mid < 90 ? (min: graphView.yRange.min, max: graphView.yRange.min + 40) : (min: mid - 20, max: mid + 20)
                }
                graphView.xRange = (min: points.reduce(Date()) { min($0, $1.date) }, max: Date())
                graphView.xTimeSpan = graphView.xRange.max - graphView.xRange.min
                graphView.records = Storage.default.lastDay.entries
                let previous = points[1]
                let trend = (current.value - previous.value) / (current.date > previous.date ? current.date - previous.date : previous.date - current.date) * 60
                let symbol = trendSymbol(for: trend)
                let levelStr = current.value > 70 ? current.value % ".0lf" : current.value % ".1lf"
                glucoseLabel?.text = "\(levelStr)\(symbol)"
                trendLabel?.text = String(format: "%.1lf", trend)
                let iob = Storage.default.insulinOnBoard(at: Date())
                if iob > 0 && UIScreen.main.bounds.width > 350.0 {
                    iobLabel?.text = "BOB\n\(iob % ".1lf")"
                    iobLabel?.isHidden = false
                } else {
                    iobLabel?.isHidden = true
                }
            }
        }
    }
    var isTriggerd = false
    var repeater: Repeater?
    func updateAgo() {
        if let current = points.first {
            let time = Int(Date() - current.date)
            agoLabel?.text = "\(time / 60):\(time % 60 % ".02ld")"
        }
    }
    func updateTime() {
        self.updateAgo()
        if repeater == nil {
            repeater = Repeater.every(1, queue: DispatchQueue.main, perform: { (_) in
                self.updateAgo()
            })
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        repeater = nil
        isTriggerd = false
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        readData()
    }
    

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateTime()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        repeater = nil
        updateAgo()
        
        ValueObservation.tracking {
            try GlucosePoint.fetchAll($0)
        }
        .publisher(in: Storage.default.trendDb)
        .receive(on: DispatchQueue.main)
        .sink { _ in
        } receiveValue: { [weak self] _ in
            self?.readData()
        }
        .store(in: &bag)
    }
        
    func readData() {
        DispatchQueue.global().async {

        do {
            let p = try Storage.default.db.unsafeRead {
                try GlucosePoint.filter(GlucosePoint.Column.date > Date() - 5.h).fetchAll($0)
            }
            let trend = try Storage.default.trendDb.unsafeRead {
                try GlucosePoint.fetchAll($0)
            }
            let np = (trend + p).sorted(by: { $0.date < $1.date })
            if  np != self.points {
                Storage.default.reloadToday()
                DispatchQueue.main.async {
                    self.points = np
                    self.updateTime()
                }

            }
        } catch {
            logError("Read error: \(error.localizedDescription)")
        }
        }
    }

    func widgetActiveDisplayModeDidChange(maximumSize maxSize: CGSize) {
            graphView.isHidden = false
    }
    
}

