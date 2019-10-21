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
        if !isTriggerd {
            isTriggerd = true
            repeater = Repeater.every(1, queue: DispatchQueue.main, perform: { (_) in
                self.updateAgo()
            })
            DispatchQueue.main.after(withDelay: 10) {
                self.isTriggerd = false
                if self.view.window != nil {
                    self.widgetPerformUpdate(completionHandler: { (result) in

                    })
                }
            }
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        coordinator = NSFileCoordinator(filePresenter: self)
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
