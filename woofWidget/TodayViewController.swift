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

private let sharedDbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "5h.sqlite"))

class TodayViewController: UIViewController {
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var agoLabel: UILabel!
    @IBOutlet var trendLabel: UILabel!
    @IBOutlet var glucoseLabel: UILabel!
    @IBOutlet var iobLabel: UILabel!
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
                glucoseLabel.text = "\(levelStr)\(symbol)"
                trendLabel.text = String(format: "%.1lf", trend)
                let iob = Storage.default.insulinOnBoard(at: Date())
                if iob > 0 && UIScreen.main.bounds.width > 350.0 {
                    iobLabel.text = "BOB\n\(iob % ".1lf")"
                    iobLabel.isHidden = false
                } else {
                    iobLabel.isHidden = true
                }
            }
        }
    }

    var isTriggerd = false
    var repeater: Repeater?
    func updateAgo() {
        if let current = points.first {
            let time = Int(Date() - current.date)
            agoLabel.text = "\(time / 60):\(time % 60 % ".02ld")"
        }
    }
    func updateTime() {
        self.updateAgo()
        if repeater == nil {
            repeater = Repeater.every(1, queue: DispatchQueue.main, perform: { (_) in
                self.updateAgo()
            })
        }
        if !isTriggerd {
            isTriggerd = true
            DispatchQueue.main.after(withDelay: 10) {
                guard self.isTriggerd else {
                    return
                }
                self.isTriggerd = false
                if self.view.window != nil {
                    self.widgetPerformUpdate()
                }
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        repeater = nil
        isTriggerd = false
    }
    
    

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateTime()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        extensionContext?.widgetLargestAvailableDisplayMode = .expanded
        repeater = nil
        updateAgo()
    }
        
    func widgetPerformUpdate(completionHandler: (() -> Void)? = nil) {
        DispatchQueue.global().async {
            let old = self.points
            do {
                let p = try Storage.default.db.read {
                    try GlucosePoint.filter(GlucosePoint.Column.date > Date() - 5.h).fetchAll($0)
                }
                let trend = try Storage.default.trendDb.read {
                    try GlucosePoint.fetchAll($0)
                }
                let np = (trend + p).sorted(by: { $0.date < $1.date })
                if  np != old {
                    Storage.default.reloadToday()
                    DispatchQueue.main.async {
                        self.points = np
                        if old.isEmpty && !self.points.isEmpty {
                            completionHandler?()
                        } else if let previousLast = old.last, let currentLast = self.points.last, currentLast.date > previousLast.date {
                            completionHandler?()
                        } else {
                            self.updateTime()
                            completionHandler?()
                        }
                    }
                } else {
                    completionHandler?()
                }
            } catch {
                logError("Read error: \(error.localizedDescription)")
                completionHandler?()
            }
        }
    }

    func widgetActiveDisplayModeDidChange(maximumSize maxSize: CGSize) {
            graphView.isHidden = false
    }
    
}

extension TodayViewController: NSFilePresenter {
    var presentedItemURL: URL? {
        return sharedDbUrl
    }

    var presentedItemOperationQueue: OperationQueue {
        return OperationQueue.main
    }


}
