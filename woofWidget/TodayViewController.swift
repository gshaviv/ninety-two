//
//  TodayViewController.swift
//  woofWidget
//
//  Created by Guy on 10/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import NotificationCenter
import Sqlable
import WoofKit
import Intents

private let sharedDbUrl = URL(fileURLWithPath: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tivstudio.woof")!.path.appending(pathComponent: "5h.sqlite"))

class TodayViewController: UIViewController, NCWidgetProviding {
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var agoLabel: UILabel!
    @IBOutlet var trendLabel: UILabel!
    @IBOutlet var glucoseLabel: UILabel!
    private let sharedDb: SqliteDatabase? = {
        let db = try? SqliteDatabase(filepath: sharedDbUrl.path)
        try! db?.createTable(GlucosePoint.self)
        return db
    }()
    private var coordinator: NSFileCoordinator!
    private var points: [GlucosePoint] = [] {
        didSet {
            if let current = points.first {
                updateTime()
                graphView.points = points
                graphView.yRange.max = ceil(graphView.yRange.max / 10) * 10
                graphView.yRange.min = floor(graphView.yRange.min / 5) * 5
                graphView.xRange = (min: points.reduce(Date()) { min($0, $1.date) }, max: Date())
                graphView.xTimeSpan = graphView.xRange.max - graphView.xRange.min
                let previous = points[1]
                let trend = (current.value - previous.value) / (current.date > previous.date ? current.date - previous.date : previous.date - current.date) * 60
                let symbol = trendSymbol(for: trend)
                glucoseLabel.text = "\(Int(round(current.value)))\(symbol)"
                trendLabel.text = String(format: "%.1lf", trend)
            }
        }
    }

    func updateTime() {
        if let current = points.first {
            let time = Int(Date().timeIntervalSince(current.date)/60)
            agoLabel.text = time == 0 ? "Now" : "\(time)m"
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        coordinator = NSFileCoordinator(filePresenter: self)
    }
    func trendSymbol(for trend: Double) -> String {
        if trend > 2.8 {
            return "⇈"
        } else if trend > 1.4 {
            return "↑"
        } else if trend > 0.5 {
            return "↗︎"
        } else if trend > -0.5 {
            return "→"
        } else if trend > -1.4 {
            return "↘︎"
        } else if trend > -2.8 {
            return "↓"
        } else {
            return "⇊"
        }
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        extensionContext?.widgetLargestAvailableDisplayMode = .expanded
        let intent = CheckGlucoseIntent()
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            // Handle error
        }
    }
        
    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        // Perform any setup necessary in order to update the view.
        
        // If an error is encountered, use NCUpdateResult.Failed
        // If there's no update required, use NCUpdateResult.NoData
        // If there's an update, use NCUpdateResult.NewData

        DispatchQueue.global().async {
            self.coordinator.coordinate(readingItemAt: sharedDbUrl, error: nil, byAccessor: { (_) in
                let old = self.points
                if let p = self.sharedDb?.evaluate(GlucosePoint.read()) {
                    DispatchQueue.main.async {
                        self.points = p.sorted(by: { $0.date > $1.date })
                        if old.isEmpty && !self.points.isEmpty {
                            completionHandler(NCUpdateResult.newData)
                        } else if let previousLast = old.last, let currentLast = self.points.last, currentLast.date > previousLast.date {
                            completionHandler(NCUpdateResult.newData)
                        } else {
                            self.updateTime()
                            completionHandler(NCUpdateResult.noData)
                        }
                    }
                }
            })
        }        
    }

    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        switch activeDisplayMode {
        case .compact:
            graphView.isHidden = true

        case .expanded:
            graphView.isHidden = false
        }
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