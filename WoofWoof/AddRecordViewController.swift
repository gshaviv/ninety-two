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
    private lazy var iob: Double = editRecord?.insulinOnBoardAtStart ?? Storage.default.insulinOnBoard(at: Date())
    private var sensitivity = Calculation {
        return Storage.default.estimateInsulinReaction()
    }
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

    var selectedDate: Date {
        var comp = Date().components
        comp.hour = picker.selectedRow(inComponent: Component.hour.rawValue)
        comp.minute = picker.selectedRow(inComponent: Component.minute.rawValue)
        comp.second = 0
        return comp.toDate()
    }

    var selectedRecord: Record {
        kind = Record.Meal(rawValue: self.picker.selectedRow(inComponent: Component.meal.rawValue) - 1)
        let u = picker.selectedRow(inComponent: Component.units.rawValue)
        if u > 0 {
            units = u
        }
        let cd = selectedDate
        let record = editRecord ?? Storage.default.lastDay.entries.first(where: { $0.date == cd }) ?? Record(date: cd, meal: nil, bolus: nil, note: nil)
        record.meal = kind
        record.bolus = units ?? 0
        if let note = noteField.text {
            record.note = note.trimmed.isEmpty ? nil : note.trimmed
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
        MiaoMiao.Command.startReading()
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
        picker.selectRow(Int(round(Double(now.minute))), inComponent: Component.minute.rawValue, animated: false)
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
            return 60

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
            return "\(row)"

        case .meal:
            return Record.Meal(rawValue: row - 1)?.name.capitalized ?? "Bolus"

        case .units:
            return "\(row)"
        }
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView.selectedRow(inComponent: Component.meal.rawValue) == 0 {
            let date = selectedDate
            if Storage.default.allMeals.first(where: { $0.date > date - 4.h && $0.date < date }) == nil, let s = sensitivity.value, let v = MiaoMiao.currentGlucose?.value  {
                let low = v + s * (Double(pickerView.selectedRow(inComponent: Component.units.rawValue)) + Storage.default.insulinOnBoard(at: Date()))
                setPrediction("Predicted @ \(Int(round(s))) [1/u] = \(max(0,Int(low)))\n\n")
                self.prediction = Storage.default.prediction(for: selectedRecord)
            } else {
                setPrediction(nil)
            }
        } else {
            predict()
        } 
        if let rec = editRecord {
            switch Component(rawValue: component)! {
            case .hour, .minute:
                var comp = rec.date.components
                comp.hour = pickerView.selectedRow(inComponent: Component.hour.rawValue)
                comp.minute = picker.selectedRow(inComponent: Component.minute.rawValue)
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



extension AddRecordViewController {


    func setPrediction(_ str: String?) {
        if let str = str {
            predictionLabel.text = str
            if iob > 0 {
                predictionLabel.text = "\(str), BOB=\(iob.formatted(with: "%.1lf"))U"
            }
            predictionLabel.alpha = 1
        } else {
            predictionLabel.text = "No prediction available\n\n"
            if iob > 0 {
                predictionLabel.text = "BOB = \(iob.formatted(with: "%.1lf"))U\n\n"
            }
            predictionLabel.alpha = 0.5
        }
    }

    @objc func predict() {
        let record = selectedRecord
        queue.async {
            guard let p = Storage.default.prediction(for: record) else {
                DispatchQueue.main.async {
                    self.setPrediction(nil)
                }
                return
            }
            DispatchQueue.main.async {
                if p.h50 > p.h10  {
                    self.setPrediction("\(p.mealCount) comparable meals\n\(p.h10)<\(p.h50)<\(p.h90) @ \(String(format: "%02ld:%02ld",p.highDate.hour, p.highDate.minute))\nLow ≥ \(p.low)")
                } else {
                    self.setPrediction("\(p.mealCount) comparable meals\n\(p.h50) @ \(String(format: "%02ld:%02ld",p.highDate.hour, p.highDate.minute))\nLow ≥ \(p.low)")
                }
                self.prediction = p
            }
        }
    }
}


extension AddRecordViewController: AutoComleteTextFieldDataSource {
    func autocompleteAttributedCompletions(textField: AutoComleteTextField, text: String) -> [NSAttributedString] {
        return picker.selectedRow(inComponent: Component.meal.rawValue) == 0 ? [] : mealNotes.filter { $0.string.hasPrefix(text) }
    }
}
