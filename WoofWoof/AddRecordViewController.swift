//
//  AddMealViewController.swift
//  WoofWoof
//
//  Created by Guy on 18/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit
import Sqlable

class AddRecordViewController: ActionSheetController {
    @IBOutlet var picker: UIPickerView!
    @IBOutlet var noteField: AutoComleteTextField!
    @IBOutlet var predictionLabel: UILabel!
    @IBOutlet var selectButton: UIButton!
    @IBOutlet var cancelButton: UIButton!
    var kind: Record.Meal?
    var units: Int?
    var editRecord: Record?
    private enum Component: Int {
        case hour
        case minute
        case meal
        case units
    }
    private var prediction: Prediction?
    private lazy var readings: [GlucosePoint] = Storage.default.db.evaluate(GlucosePoint.read().orderBy(GlucosePoint.date)) ?? []
    private lazy var meals: [Record] = Storage.default.db.evaluate(Record.read().filter(Record.meal != Null()).orderBy(Record.date)) ?? []
    private lazy var mealNotes: [String] = {
        return meals.compactMap { $0.note }.sorted()
    }()
    var onSelect: ((inout Record, Prediction?) -> Void)?
    var onCancel: (() -> Void)?
    private let queue = DispatchQueue(label: "predict")

    @IBAction func handleCancel(_ sender: Any) {
        if let edit = editRecord {
            Storage.default.db.evaluate(edit.delete())
            Storage.default.reloadToday()
            if let vc = presentingViewController as? ViewController {
                vc.graphView.records = Storage.default.lastDay.entries
            }
            dismiss(animated: true, completion: nil)
        } else {
            onSelect = nil
            dismiss(animated: true) {
                self.onCancel?()
                self.onCancel = nil
            }
        }
    }

    @IBAction func handleSelect(_ sender: Any) {
        var comp = Date().components
        comp.hour = picker.selectedRow(inComponent: Component.hour.rawValue)
        comp.minute = picker.selectedRow(inComponent: Component.minute.rawValue) * 5
        comp.second = 0
        guard let k = Record.Meal(rawValue: self.picker.selectedRow(inComponent: Component.meal.rawValue) - 1) else {
            return
        }
        kind = k
        let u = picker.selectedRow(inComponent: Component.units.rawValue)
        if u > 0 {
            units = u
        }
        let cd = comp.toDate()
        var record = editRecord ?? Storage.default.lastDay.entries.first(where: { $0.date == cd }) ?? Record(date: cd, meal: nil, bolus: nil, note: nil)
        record.meal = kind
        record.bolus = units ?? 0
        if let note = noteField.text, !note.trimmed.isEmpty {
            record.note = note.trimmed
        }

        if let _ = editRecord {
            var comp = record.date.components
            comp.hour = picker.selectedRow(inComponent: Component.hour.rawValue)
            comp.minute = picker.selectedRow(inComponent: Component.minute.rawValue) * 5
            record.date = comp.toDate()
            Storage.default.db.evaluate(record.update())
        }

        dismiss(animated: true) {
            self.onSelect?(&record, self.prediction)
            self.onSelect = nil
            self.onCancel = nil
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        predict()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        var now = Date()
        if now.minute > 57 {
            var comp = now.components
            comp.minute = 0
            comp.hour = now.hour + 1
            now = comp.toDate()
        }
        if let edit = editRecord {
            now = edit.date
            units = edit.bolus
            kind = edit.meal
            noteField.text = edit.note
            cancelButton.setTitle("Delete", for: .normal)
            selectButton.setTitle("Save", for: .normal)
        }

        picker.selectRow(now.hour, inComponent: Component.hour.rawValue, animated: false)
        picker.selectRow(Int(round(Double(now.minute) / 5.0)), inComponent: Component.minute.rawValue, animated: false)
        if let kind = kind {
            picker.selectRow(kind.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
        } else {
            switch now.hour {
            case 5...10:
                picker.selectRow(Record.Meal.breakfast.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
            case 11...14:
                picker.selectRow(Record.Meal.lunch.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
            case 18...21:
                picker.selectRow(Record.Meal.dinner.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
            default:
                picker.selectRow(0, inComponent: Component.meal.rawValue, animated: false)
            }
        }
        if let units = units {
            picker.selectRow(units, inComponent: Component.units.rawValue, animated: false)
        }
        setPrediction(nil)
        preferredContentSize = CGSize(width: 420, height: view.systemLayoutSizeFitting(CGSize(width: 420, height: 1000)).height)
        NotificationCenter.default.addObserver(self, selector: #selector(predict), name: UITextField.textDidChangeNotification, object: noteField)
    }

}

extension AddRecordViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 4
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch Component(rawValue: component)! {
        case .hour:
            return 24

        case .minute:
            return 12

        case .meal:
            return 5

        case .units:
            return 50
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch Component(rawValue: component)! {
        case .hour:
            return "\(row)"

        case .minute:
            return "\(row * 5)"

        case .meal:
            return Record.Meal(rawValue: row - 1)?.name.capitalized ?? "None"

        case .units:
            return "\(row)"
        }
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView.selectedRow(inComponent: Component.meal.rawValue) == 0 {
            self.predictionLabel.isHidden = true
            self.predictionLabel.text = nil
        } else {
            predict()
        }
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        switch Component(rawValue: component)! {
        case .hour:
            return 40

        case .minute:
            return 40

        case .meal:
            return 180

        case .units:
            return 40
        }
    }
}

extension AddRecordViewController: UITextFieldDelegate {
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return true
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

public func mealStatistics(meal: Record, points mealPoints: [GlucosePoint]) -> (Double, TimeInterval, Double) {
    var highest = mealPoints[0]
    var lowestAfterHigh = mealPoints[0]
    for point in mealPoints[1...] {
        if point.value > highest.value {
            highest = point
            lowestAfterHigh = point
        } else if point.value < highest.value && point.value < lowestAfterHigh.value {
            lowestAfterHigh = point
        }
    }
    return (highest.value - mealPoints[0].value, highest.date - meal.date, lowestAfterHigh.value - mealPoints[0].value)
}

extension AddRecordViewController {


    func setPrediction(_ str: String?) {
        if let str = str {
            predictionLabel.text = str
            predictionLabel.alpha = 1
        } else {
            predictionLabel.text = "No prediction available\n"
            predictionLabel.alpha = 0.5
        }
    }

    @objc func predict() {
        guard let kind = Record.Meal(rawValue: picker.selectedRow(inComponent: Component.meal.rawValue) - 1), editRecord == nil else {
            setPrediction(nil)
            return
        }
        let note = noteField.text ?? ""
        let units = picker.selectedRow(inComponent: Component.units.rawValue)
        queue.async {
            guard let current = MiaoMiao.currentGlucose else {
                DispatchQueue.main.async {
                    self.setPrediction(nil)
                }
                return
            }
            var relevantMeals = self.meals.filter { $0.meal == kind && $0.bolus == units }
            if !note.isEmpty {
                let posible = relevantMeals.filter { $0.note?.hasPrefix(note) == true }
                if !posible.isEmpty {
                    relevantMeals = posible
                }
            }
            var points = [[GlucosePoint]]()
            guard !relevantMeals.isEmpty else {
                DispatchQueue.main.async {
                    self.setPrediction(nil)
                }
                return
            }
            for meal in relevantMeals {
                let nextEvent = self.meals.first(where: { $0.date > meal.date })
                let nextDate = nextEvent?.date ?? Date.distantFuture
                let relevantPoints = self.readings.filter { $0.date >= meal.date && $0.date <= nextDate && $0.date < meal.date + 5.h }
                points.append(relevantPoints)
            }
            var highs: [Double] = []
            var lows: [Double] = []
            var timeToHigh: [TimeInterval] = []
            for (meal, mealPoints) in zip(relevantMeals, points) {
                if mealPoints.count < 2 {
                    continue
                }
                let stat = mealStatistics(meal: meal, points: mealPoints)
                highs.append(stat.0)
                lows.append(stat.2)
                timeToHigh.append(stat.1)
            }
            let predictedHigh = Int(round(highs.sorted().median() + current.value))
            let predictedHigh25 = Int(round(highs.sorted().percentile(0.25) + current.value))
            let predictedHigh75 = Int(round(highs.sorted().percentile(0.75) + current.value))
            let predictedLow = Int(round(lows.sorted().median() + current.value))
            let predictedLow10 = Int(round(lows.sorted().percentile(0.1) + current.value))
            let predictedTime = Date() + timeToHigh.sorted().median()
            DispatchQueue.main.async {
                if predictedHigh > predictedHigh25 && predictedLow > predictedLow10 {
                    self.setPrediction("\(predictedHigh25)-\(predictedHigh)-\(predictedHigh75) @ \(String(format: "%02ld:%02ld",predictedTime.hour, predictedTime.minute))\nLow = \(predictedLow), 90% above \(predictedLow10)")
                } else if predictedHigh > predictedHigh25 {
                    self.setPrediction("\(predictedHigh25)-\(predictedHigh)-\(predictedHigh75) @ \(String(format: "%02ld:%02ld",predictedTime.hour, predictedTime.minute))\nLow = \(predictedLow)")
                } else {
                    self.setPrediction("\(predictedHigh) @ \(String(format: "%02ld:%02ld",predictedTime.hour, predictedTime.minute))\nLow = \(predictedLow)")
                }
                self.prediction = Prediction(highDate: predictedTime, h25: CGFloat(predictedHigh25), h50: CGFloat(predictedHigh), h75: CGFloat(predictedHigh75), lowDate: Date() + 3.h, low: CGFloat(predictedLow10))
            }
        }
    }
}


extension AddRecordViewController: AutoComleteTextFieldDataSource {
    func autocomplete(textField: AutoComleteTextField, text: String) -> [String] {
        return mealNotes.filter { $0.hasPrefix(text) }
    }
}
