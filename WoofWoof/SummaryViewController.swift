//
//  SummaryViewController.swift
//  WoofWoof
//
//  Created by Guy on 24/02/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit
import SwiftUI
import Combine

var summary = SummaryInfo(Summary(period: defaults.summaryPeriod, timeInRange: Summary.TimeInRange(low: 1, inRange: 1, high: 1), maxLevel: 180, minLevel: 70, average: 92, a1c: Summary.EA1C(value: 6.1, range: 0.1), low: Summary.Low(count: 0, median: 0), atdd: 0, timeInLevel: [1,1,1,1,1,1], daily: [], date: Date()))

class SummaryViewController: UIHostingController<SummaryView> {
    private var listen: NSObjectProtocol?
    private var action = Action<SummaryActions>()
    private var actionListener: AnyCancellable?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: SummaryView(summary: summary, action: action))
        preferredContentSize = CGSize(width: 375, height: (UIFont.preferredFont(forTextStyle: .body).pointSize + 5) * 7)
        listen = NotificationCenter.default.addObserver(forName: UserDefaults.notificationForChange(UserDefaults.IntKey.summaryPeriod), object: nil, queue: OperationQueue.main) { (_) in
            self.updateSummary()
        }
        actionListener = action.sink { [weak self] in
            switch $0 {
            case .period:
                self?.changePeriod()
                
            case .dailyAverage:
                self?.navigationController?.pushViewController(AveHistoryController(), animated: true)
                
            case .dailyLows:
                self?.navigationController?.pushViewController(LowEventsViewController(), animated: true)
                
            case .dailyDose:
                self?.navigationController?.pushViewController(DoseHistoryController(), animated: true)
                
            case .dailyRange:
                self?.navigationController?.pushViewController(RangeHistoryController(), animated: true)
            }
        }
    }
    
    override func viewDidLoad() {
        updateSummary()
        super.viewDidLoad()        
    }
    
    @objc public func updateSummary(completion: ((Bool)->Void)? = nil) {
        summary.update {
            completion?($0)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
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

