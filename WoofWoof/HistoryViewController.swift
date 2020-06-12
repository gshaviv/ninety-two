//
//  HistoryViewController.swift
//  WoofWoof
//
//  Created by Guy on 31/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import Sqlable
import WoofKit

class HistoryViewController: UIViewController {
    private var lastTouchedRecord: Record?
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var backButton: UIButton!
    @IBOutlet var forwardButton: UIButton!
    @IBOutlet var dateLabel: UILabel!
    @IBOutlet var timeSpanSelector: UISegmentedControl!
    private var timeSpan = [24.h, 12.h, 6.h, 4.h, 2.h, 1.h]
    var onSummaryVC: ((UINavigationController) -> Void)?

    var displayDay: Date! {
        didSet {
            guard isViewLoaded, let displayDay = displayDay else {
                return
            }
            updateControls()
            graphView.records = Storage.default.allEntries.filter { $0.date > displayDay.startOfDay && $0.date < displayDay.endOfDay }
            graphView.points = Storage.default.db.evaluate(GlucosePoint.read().filter(Record.date > displayDay.startOfDay && Record.date < displayDay.endOfDay).orderBy(Record.date))
            graphView.xRange.min = displayDay.startOfDay
            graphView.xRange.max = displayDay.endOfDay

            var buckets = Array(repeating: [Double](), count: 24)
            let dateRange = ceil((Date() - displayDay) / 7.d) * 7.d
            let readings = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > displayDay - dateRange && GlucosePoint.date < displayDay + dateRange)) ?? []
            readings.forEach {
                let inBucket = Int(($0.date - $0.date.startOfDay) / 3600.0)
                if inBucket < buckets.count {
                buckets[inBucket].append($0.value)
                }
            }

            var p25 = [Double]()
            var p10 = [Double]()
            var p50 = [Double]()
            var p75 = [Double]()
            var p90 = [Double]()
            for range in [(buckets.count - 1) ..< buckets.count, 0 ..< buckets.count, 0 ..< 1] {
                for idx in range {
                    if buckets[idx].count < 2 {
                        return
                    }
                    buckets[idx] = buckets[idx].sorted()
                    p50.append(buckets[idx].median())
                    p10.append(buckets[idx].percentile(0.1))
                    p25.append(buckets[idx].percentile(0.25))
                    p75.append(buckets[idx].percentile(0.75))
                    p90.append(buckets[idx].percentile(0.9))
                }
            }

            graphView.pattern = Pattern(p10: p10, p25: p25, p50: p50, p75: p75, p90: p90)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        timeSpanSelector.selectedSegmentIndex = defaults[.timeSpanIndex]
        graphView.xTimeSpan = timeSpan[defaults[.timeSpanIndex]]
        graphView.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let displayDay = displayDay {
            self.displayDay = displayDay
            DispatchQueue.main.async {
                self.graphView.scroll(to: displayDay)
            }
        } else {
            displayDay = Date().startOfDay - 12.h
        }
    }

    func updateControls() {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        dateLabel.text = formatter.string(from: displayDay)
        forwardButton.isEnabled = displayDay.endOfDay + 24.h < Date()
    }

    @IBAction func handleBack() {
        displayDay -= 1.d
    }

    @IBAction func handleForward() {
        displayDay += 1.d
    }

    @IBAction func selectedTimeSpan(_ sender: UISegmentedControl) {
        defaults[.timeSpanIndex] = sender.selectedSegmentIndex
        graphView.xTimeSpan = timeSpan[sender.selectedSegmentIndex]
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.destination {
        case let ctr as DatePickerViewController:
            if displayDay > Date() - 2.d {
                ctr.startDate = Date() - defaults.summaryPeriod.d
            } else {
                ctr.startDate = displayDay
            }
            ctr.onSelect = {
                self.displayDay = $0
            }

        case let nav as UINavigationController:
            switch nav.viewControllers[0] {
            case let c as RecordViewController:
                if let r = sender as? Record {
                    c.editRecord = r
                    c.onSelect = { (_,prediction) in
                        self.graphView.prediction = prediction
                        Storage.default.reloadToday()
                        self.graphView.records = Storage.default.allEntries.filter { $0.date > self.displayDay.startOfDay && $0.date < self.displayDay.endOfDay }
                    }
                    c.onCancel = {
                        self.graphView.prediction = nil
                    }
                }

            default:
                onSummaryVC?(nav)
                onSummaryVC = nil
            }

        default:
            break
        }
    }
}

extension HistoryViewController: GlucoseGraphDelegate {
    func didDoubleTap(record: Record) {
        self.performSegue(withIdentifier: "addRecord", sender: record)
    }

    func didTouch(record: Record) {
        guard record.isMeal else {
            return
        }

        DispatchQueue.global().async {
            let prediction: Prediction?
            if let last = self.lastTouchedRecord, last.id == record.id {
                prediction =  Storage.default.calculatedLevel(for: record)
            } else {
                prediction = Storage.default.prediction(for: record) ?? Storage.default.calculatedLevel(for: record)
            }
            self.lastTouchedRecord = record
            DispatchQueue.main.after(withDelay: 3, closure: {
                self.lastTouchedRecord = nil
            })
            DispatchQueue.main.async {
                self.graphView.prediction = prediction
            }
        }
    }
}

class DatePickerViewController: ActionSheetController {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet private var mainStackView: UIStackView!
    @IBOutlet var picker: UIDatePicker!
    var startDate: Date?
    var onSelect: ((Date) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        if let startDate = startDate {
            picker.date = startDate
        }
        preferredContentSize = mainStackView.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width, height: 0), withHorizontalFittingPriority: UILayoutPriority.required, verticalFittingPriority: UILayoutPriority.fittingSizeLevel)
    }

    @IBAction func handleCancel() {
        onSelect = nil
        dismiss(animated: true, completion: nil)
    }

    @IBAction func handleSet() {
        onSelect?(picker.date)
        onSelect = nil
        dismiss(animated: true, completion: nil)
    }

    @IBAction func dateChanged() {
        let d = picker.date
        if let day = d.components.weekday {
            titleLabel.text = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day - 1]
        }
    }
}


