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
    @IBOutlet var deleteButton: UIButton!
    var kind: Record.Meal?
    var units: Int?
    var note: String?
    var editRecord: Record?
    private enum Component: Int {
        case hour
        case minute
        case meal
        case units
    }
    private var prediction: Prediction?
    private lazy var readings: [GlucosePoint] = Storage.default.db.evaluate(GlucosePoint.read().orderBy(GlucosePoint.date)) ?? []
    private let meals = Storage.default.allMeals
    private lazy var mealNotes: [NSAttributedString] = {
        let fromMeals = meals.compactMap { $0.note }.unique().sorted()
        let setFromMeals = Set(fromMeals)
        let additionalWords = words.filter { !setFromMeals.contains($0) }.sorted()
        return fromMeals.map { $0.styled.traits(.traitBold) } + additionalWords.map { $0.styled }
    }()
    var onSelect: ((Record, Prediction?) -> Void)?
    var onCancel: (() -> Void)?
    private let queue = DispatchQueue(label: "predict")
    private lazy var words: [String] = {
        let all = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: Bundle(for: Storage.self).path(forResource: "words", ofType: "json")!)), options: []) as! [String: Any]
        var wordList: [String] = []
        for (_,value) in all {
            if let list = value as? [String] {
                wordList += list.map { $0.capitalized }
            }
        }
        return wordList.sorted()
    }()
    private lazy var iob: Double = Storage.default.insulinOnBoard(at: Date())

    @IBAction func handleCancel(_ sender: Any) {
        onSelect = nil
        dismiss(animated: true) {
            self.onCancel?()
            self.onCancel = nil
        }
    }

    @IBAction func handleDelete() {
        onSelect = nil
        if let edit = editRecord {
            Storage.default.db.evaluate(edit.delete())
            Storage.default.reloadToday()
        }
        dismiss(animated: true) {
            self.onCancel?()
            self.onCancel = nil
        }
    }

    var selectedRecord: Record {
        var comp = Date().components
        comp.hour = picker.selectedRow(inComponent: Component.hour.rawValue)
        comp.minute = picker.selectedRow(inComponent: Component.minute.rawValue) * 5
        comp.second = 0
        kind = Record.Meal(rawValue: self.picker.selectedRow(inComponent: Component.meal.rawValue) - 1)
        let u = picker.selectedRow(inComponent: Component.units.rawValue)
        if u > 0 {
            units = u
        }
        let cd = comp.toDate()
        let record = editRecord ?? Storage.default.lastDay.entries.first(where: { $0.date == cd }) ?? Record(date: cd, meal: nil, bolus: nil, note: nil)
        record.meal = kind
        record.bolus = units ?? 0
        if let note = noteField.text, !note.trimmed.isEmpty {
            record.note = note.trimmed
        }
        return record
    }

    @IBAction func handleSelect(_ sender: Any) {
        let record = selectedRecord

        guard record.isMeal || record.isBolus else {
            return
        }

        if let _ = editRecord {
            Storage.default.db.evaluate(record.update())
            Storage.default.reloadToday()
        }

        dismiss(animated: true) {
            self.onSelect?(record, self.prediction)
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
            note = edit.note
            selectButton.setTitle("Save", for: .normal)
            deleteButton.isHidden = false
        } else {
            deleteButton.isHidden = true
        }

        noteField.text = note
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
        view.translatesAutoresizingMaskIntoConstraints = false
        preferredContentSize = CGSize(width: 420, height: view.systemLayoutSizeFitting(CGSize(width: 420, height: 1000)).height)
        view.translatesAutoresizingMaskIntoConstraints = true
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
        if let rec = editRecord {
            switch Component(rawValue: component)! {
            case .hour, .minute:
                var comp = rec.date.components
                comp.hour = pickerView.selectedRow(inComponent: Component.hour.rawValue)
                comp.minute = picker.selectedRow(inComponent: Component.minute.rawValue) * 5
                editRecord?.date = comp.toDate()

            case .units:
                editRecord?.bolus = picker.selectedRow(inComponent: Component.units.rawValue)

            case .meal:
                guard let k = Record.Meal(rawValue: self.picker.selectedRow(inComponent: Component.meal.rawValue) - 1) else {
                    return
                }
                editRecord?.meal = k
            }
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
            if iob > 0 {
                predictionLabel.text = "\(str), IOB=\(iob.formatted(with: "%.1lf"))U"
            }
            predictionLabel.alpha = 1
        } else {
            predictionLabel.text = "No prediction available\n"
            if iob > 0 {
                predictionLabel.text = "IOB = \(iob.formatted(with: "%.1lf"))U"
            }
            predictionLabel.alpha = 0.5
        }
    }

    @objc func predict() {
        let record = selectedRecord
        queue.async {
            guard let current = MiaoMiao.currentGlucose else {
                DispatchQueue.main.async {
                    self.setPrediction(nil)
                }
                return
            }
            let relevantMeals = Storage.default.relevantMeals(to: record)
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
                self.prediction = Prediction(mealTime: current.date, highDate: predictedTime, h25: CGFloat(predictedHigh25), h50: CGFloat(predictedHigh), h75: CGFloat(predictedHigh75), low: CGFloat(predictedLow10))
            }
        }
    }
}


extension AddRecordViewController: AutoComleteTextFieldDataSource {
    func autocompleteAttributedCompletions(textField: AutoComleteTextField, text: String) -> [NSAttributedString] {
        return picker.selectedRow(inComponent: Component.meal.rawValue) == 0 ? [] : mealNotes.filter { $0.string.hasPrefix(text) }
    }
}
