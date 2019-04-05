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
    @IBOutlet var iobLabel: UILabel!
    private let sharedDb: SqliteDatabase? = {
        defaults.register()
        let db = try? SqliteDatabase(filepath: sharedDbUrl.path)
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
                graphView.records = Storage.default.lastDay.entries
                let previous = points[1]
                let trend = (current.value - previous.value) / (current.date > previous.date ? current.date - previous.date : previous.date - current.date) * 60
                let symbol = trendSymbol(for: trend)
                glucoseLabel.text = "\(Int(round(current.value)))\(symbol)"
                trendLabel.text = String(format: "%.1lf", trend)
                let iob = Storage.default.insulinOnBoard(at: Date())
                if iob > 0 && UIScreen.main.bounds.width > 350.0 {
                    iobLabel.text = "BOB\n\(iob.formatted(with: "%.1lf"))"
                    iobLabel.isHidden = false
                } else {
                    iobLabel.isHidden = true
                }
            }
        }
    }

    var isTriggerd = false
    func updateTime() {
        if let current = points.first {
            let time = Int(Date().timeIntervalSince(current.date)/60)
            agoLabel.text = time == 0 ? "Now" : "\(time)m"
        }
        if !isTriggerd {
            isTriggerd = true
            DispatchQueue.main.after(withDelay: 20) {
                self.isTriggerd = false
                if self.view.window != nil {
                    self.widgetPerformUpdate(completionHandler: { (_) in

                    })
                }
            }
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
        intent.suggestedInvocationPhrase = "What's my glucose"
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            // Handle error
        }
    }
        
    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        DispatchQueue.global().async {
            self.coordinator.coordinate(readingItemAt: sharedDbUrl, error: nil, byAccessor: { (_) in
                let old = self.points
                if let p = self.sharedDb?.evaluate(GlucosePoint.read()) {
                    Storage.default.db.async {
                        Storage.default.reloadToday()
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

        @unknown default:
            graphView.isHidden = true
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
