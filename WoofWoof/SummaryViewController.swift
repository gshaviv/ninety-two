//
//  SummaryViewController.swift
//  WoofWoof
//
//  Created by Guy on 24/02/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit
import Sqlable
import SwiftUI
import Combine

var summary = SummaryInfo(Summary(period: defaults.summaryPeriod, timeInRange: Summary.TimeInRange(low: 1, inRange: 1, high: 1), maxLevel: 180, minLevel: 70, average: 92, a1c: 6.0, low: Summary.Low(count: 0, median: 0), atdd: 0, timeInLevel: [1,1,1,1,1,1]))

class SummaryViewController: UIHostingController<SummaryView> {
    private var listen: NSObjectProtocol?
    private var action = Action()
    private var actionListener: AnyCancellable?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: SummaryView(summary: summary, action: action))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        preferredContentSize = CGSize(width: 375, height: (UIFont.preferredFont(forTextStyle: .body).pointSize + 5) * 7)
        
        updateSummary()
        listen = NotificationCenter.default.addObserver(forName: UserDefaults.notificationForChange(UserDefaults.IntKey.summaryPeriod), object: nil, queue: OperationQueue.main) { (_) in
            self.updateSummary()
        }
        actionListener = action.sink {
            self.changePeriod()
        }
    }
    
    @objc public func updateSummary(completion: ((Bool)->Void)? = nil) {
        summary.update {
            if $0 {
                defaults[.needUpdateSummary] = true
            }
            completion?($0)
        }
    }
    
    private func changePeriod() {
        let ctr = UIStoryboard(name: "Settings", bundle: nil).instantiateViewController(withIdentifier: "enum") as! EnumViewController
        ctr.count = UserDefaults.summaryPeriods.count
        ctr.title = "Summary Timeframe"
        ctr.value = defaults[.summaryPeriod]
        ctr.setter = {
            defaults[.summaryPeriod] = $0
        }
        ctr.getValue = {
            $0 == 0 ? "24 hours" : "\(UserDefaults.summaryPeriods[$0]) days"
        }
        present(ctr, animated: true, completion: nil)
    }

}

