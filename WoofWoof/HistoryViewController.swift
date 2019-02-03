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
    @IBOutlet var graphView: GlucoseGraph!
    @IBOutlet var percentLowLabel: UILabel!
    @IBOutlet var aveGlucoseLabel: UILabel!
    @IBOutlet var percentInRangeLabel: UILabel!
    @IBOutlet var a1cLabel: UILabel!
    @IBOutlet var percentHighLabel: UILabel!
    @IBOutlet var pieChart: PieChart!
    @IBOutlet var backButton: UIButton!
    @IBOutlet var forwardButton: UIButton!
    @IBOutlet var dateLabel: UILabel!
    @IBOutlet var timeSpanSelector: UISegmentedControl!
    private var timeSpan = [24.h, 12.h, 6.h, 4.h, 2.h, 1.h]

    var displayDay: Date! {
        didSet {
            guard let displayDay = displayDay else {
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
                buckets[inBucket].append($0.value)
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
        displayDay = Date().startOfDay - 12.h
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

    @IBAction func setDate() {
        guard let ctr = storyboard?.instantiateViewController(withIdentifier: "setDate") as? DatePickerViewController else {
            return
        }
        ctr.startDate = displayDay
        ctr.onSelect = {
            self.displayDay = $0
        }
        present(ctr, animated: true, completion: nil)
    }
}

extension HistoryViewController: GlucoseGraphDelegate {
    func didDoubleTap(record: Record) {
        let ctr = AddRecordViewController()
        ctr.editRecord = record
        ctr.onSelect = { (_,_) in
            self.graphView.prediction = nil
            self.graphView.records = Storage.default.lastDay.entries
        }
        ctr.onCancel = {
            self.graphView.prediction = nil
            self.graphView.records = Storage.default.lastDay.entries
        }
        present(ctr, animated: true, completion: nil)
    }

    func didTouch(record: Record) {
        guard record.isMeal else {
            return
        }

        DispatchQueue.global().async {
            let readings = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date < record.date).orderBy(GlucosePoint.date)) ?? []
            guard let current = readings.last else {
                return
            }
            let meals = Storage.default.allMeals.filter { $0.date < record.date  }
            let relevantMeals = Storage.default.relevantMeals(to: record)
            var points = [[GlucosePoint]]()
            guard !relevantMeals.isEmpty else {
                return
            }
            for meal in relevantMeals {
                let nextEvent = meals.first(where: { $0.date > meal.date })
                let nextDate = nextEvent?.date ?? Date.distantFuture
                let relevantPoints = readings.filter { $0.date >= meal.date && $0.date <= nextDate && $0.date < meal.date + 5.h }
                points.append(relevantPoints)
            }
            var highs: [Double] = []
            var lows: [Double] = []
            var timeToHigh: [TimeInterval] = []
            for (meal, mealPoints) in zip(relevantMeals, points) {
                guard mealPoints.count > 2 else {
                    continue
                }
                let stat = mealStatistics(meal: meal, points: mealPoints)
                highs.append(stat.0)
                lows.append(stat.2)
                timeToHigh.append(stat.1)
            }
            if highs.count < 2 {
                return
            }
            let predictedHigh = CGFloat(round(highs.sorted().median() + current.value))
            let predictedHigh25 = CGFloat(round(highs.sorted().percentile(0.2) + current.value))
            let predictedHigh75 = CGFloat(round(highs.sorted().percentile(0.8) + current.value))
            let predictedLow = CGFloat(round(lows.sorted().percentile(0.1) + current.value))
            let predictedTime = record.date + timeToHigh.sorted().median()
            DispatchQueue.main.async {
                self.graphView.prediction = Prediction(mealTime: record.date, highDate: predictedTime, h25: predictedHigh25, h50: predictedHigh, h75: predictedHigh75, low: predictedLow)
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


