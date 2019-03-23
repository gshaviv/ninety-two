//
//  RecordViewController.swift
//  WoofWoof
//
//  Created by Guy on 16/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import UIKit
import WoofKit
import Sqlable

class RecordViewController: UIViewController {
    @IBOutlet var picker: UIPickerView!
    @IBOutlet var noteField: AutoComleteTextField!
    @IBOutlet var predictionLabel: UILabel!
    @IBOutlet var mealTable: UITableView!
    @IBOutlet var mealHeader: UILabel!
    @IBOutlet var deleteButton: UIBarButtonItem!
    private var prediction: Prediction?
    var onSelect: ((Record, Prediction?) -> Void)?
    var onCancel: (() -> Void)?
    private let queue = DispatchQueue(label: "predict")
    var meal = Meal(name: nil)
    var editRecord: Record? {
        didSet {
            if let meal = editRecord?.meal {
                self.meal = meal
            }
            title = editRecord == nil ? "Add Record" : "Edit Record"
        }
    }
    private lazy var iob: Double = editRecord?.insulinOnBoardAtStart ?? Storage.default.insulinOnBoard(at: Date())

    private enum Component: Int {
        case hour
        case minute
        case meal
        case units
    }
    var selectedDate: Date {
        var comp = Date().components
        comp.hour = picker.selectedRow(inComponent: Component.hour.rawValue)
        comp.minute = picker.selectedRow(inComponent: Component.minute.rawValue)
        comp.second = 0
        return comp.toDate()
    }
    private var sensitivity = Calculation {
        return Storage.default.estimateInsulinReaction()
    }
    private lazy var mealNotes: [NSAttributedString] = {
        let fromMeals = Storage.default.allMeals.compactMap { $0.note }.unique().sorted()
        let setFromMeals = Set(fromMeals)
        let additionalWords = words.filter { !setFromMeals.contains($0) }.sorted()
        return fromMeals.map { $0.styled.traits(.traitBold) } + additionalWords.map { $0.styled }
    }()
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
    var selectedRecord: Record {
        let cd = selectedDate
        let record = editRecord ?? Storage.default.lastDay.entries.first(where: { $0.date == cd }) ?? Record(date: cd, meal: nil, bolus: nil, note: nil)
        record.type = Record.MealType(rawValue: self.picker.selectedRow(inComponent: Component.meal.rawValue) - 1)
        record.bolus = picker.selectedRow(inComponent: Component.units.rawValue)
        record.carbs = meal.totalCarbs
        if let note = noteField.text {
            record.note = note.trimmed.isEmpty ? nil : note.trimmed
            if meal.id == nil {
                meal.name = record.note
            }
        } 

        return record
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        noteField.resignFirstResponder()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        noteField.text = meal.name
        var now = Date()
        if now.minute > 58 {
            var comp = now.components
            comp.minute = 0
            comp.hour = now.hour + 1
            now = comp.toDate()
        }
        if let edit = editRecord {
            now = edit.date
            deleteButton.isEnabled = true
        } else {
            deleteButton.isEnabled = false
        }
        noteField.text = editRecord?.note
        picker.selectRow(now.hour, inComponent: Component.hour.rawValue, animated: false)
        picker.selectRow(Int(round(Double(now.minute))), inComponent: Component.minute.rawValue, animated: false)
        if let kind = editRecord?.type {
            picker.selectRow(kind.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
        } else {
            switch now.hour {
            case 5...10:
                picker.selectRow(Record.MealType.breakfast.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
            case 11...14:
                picker.selectRow(Record.MealType.lunch.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
            case 18...21:
                picker.selectRow(Record.MealType.dinner.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
            default:
                picker.selectRow(0, inComponent: Component.meal.rawValue, animated: false)
            }
        }
        if let units = editRecord?.bolus {
            picker.selectRow(units, inComponent: Component.units.rawValue, animated: false)
        }
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
            edit.discard()
            Storage.default.reloadToday()
        }
        dismiss(animated: true) {
            self.onCancel?()
            self.onCancel = nil
        }
    }

    @IBAction func handleSave() {
        let record = selectedRecord
        if record.isMeal {
            if meal.id == nil {
                try! meal.save()
            }
            if let mealId = record.mealId, mealId != meal.id {
                if let records = Storage.default.db.evaluate(Record.read().filter(Record.mealId == mealId)), records.count == 1 {
                    record.meal.discard(db: Storage.default.db)
                }
            }
            record.mealId = meal.id
        }
        record.save(to: Storage.default.db)
        onCancel = nil
        dismiss(animated: true) {
            self.onSelect?(record, self.prediction)
            self.onSelect = nil
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.destination {
        case let ctr as PrepareMealViewController:
            ctr.delegate = self

        default:
            break
        }
    }
}

extension RecordViewController: UIPickerViewDelegate, UIPickerViewDataSource {
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
            return Record.MealType(rawValue: row - 1)?.name.capitalized ?? "Bolus"

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
                guard let k = Record.MealType(rawValue: self.picker.selectedRow(inComponent: Component.meal.rawValue) - 1) else {
                    return
                }
                editRecord?.type = k
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

extension RecordViewController: UITextFieldDelegate {
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return true
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}


extension RecordViewController: AutoComleteTextFieldDataSource {
    func autocompleteAttributedCompletions(textField: AutoComleteTextField, text: String) -> [NSAttributedString] {
        return picker.selectedRow(inComponent: Component.meal.rawValue) == 0 ? [] : mealNotes.filter { $0.string.hasPrefix(text) }
    }
}

extension RecordViewController: PrepareMealViewControllerDelegate {
    func didSelectMeal(_ selectedMeal: Meal) {
        if meal.id == nil {
            if meal.servingCount == 0 {
                meal = selectedMeal
                noteField.text = meal.name
            } else {
                selectedMeal.servings.forEach {
                    meal.append($0)
                }
            }
        } else {
            let appendedMeal = Meal(name: noteField.text)
            meal.servings.forEach {
                appendedMeal.append($0)
            }
            selectedMeal.servings.forEach {
                appendedMeal.append($0)
            }
            meal = appendedMeal
        }
        mealTable.reloadData()
    }

    func didSelectServing(_ serving: FoodServing) {
        if meal.id != nil {
            let appendedMeal = Meal(name: noteField.text)
            meal.servings.forEach {
                appendedMeal.append($0)
            }
            meal = appendedMeal
        }
        meal.append(serving)
        mealTable.reloadData()
    }

}

extension RecordViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        mealHeader.text = "Carbs: \(meal.totalCarbs.formatted(with: "%.0lf"))g"
        return meal.servingCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "serving") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "serving")
        let serving = meal[indexPath.row]
        cell.textLabel?.text = serving.food.name.capitalized
        cell.textLabel?.numberOfLines = 2
        cell.detailTextLabel?.text = "\(serving.carbs.formatted(with: "%.0lf"))g: \(serving.amount.maxDigits(3)) \(serving.food.householdName.lowercased())"
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        tableView.beginUpdates()
        tableView.deleteRows(at: [indexPath], with: .automatic)
        meal.remove(servingAt: indexPath.row)
        tableView.endUpdates()
    }
}

extension RecordViewController {
    func setPrediction(_ str: String?) {
        if let str = str {
            predictionLabel.text = str
            predictionLabel.alpha = 1
        } else {
            predictionLabel.text = "No prediction available\n\n"
            if iob > 0 {
                predictionLabel.text = "BOB = \(iob.formatted(with: "%.1lf"))U\n\n"
            }
            predictionLabel.alpha = 0.5
            self.prediction = nil
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
                if p.h50 < p.h90  && p.low50 > p.low {
                    self.setPrediction("\(p.mealCount) comparable meals\nHigh: 50%=\(p.h50), 90%<\(p.h90)\nLow: 90%>\(p.low), 50%=\(p.low50)")
                } else if p.h50 < p.h90 {
                    self.setPrediction("\(p.mealCount) comparable meals\nHigh: 50%=\(p.h50), 90%<\(p.h90)\nLow: 90%>\(p.low)")
                } else {
                    self.setPrediction("\(p.mealCount) comparable meals\n@\(String(format: "%02ld:%02ld",p.highDate.hour, p.highDate.minute)): 50%=\(p.h50)\nLow: \(p.low)")
                }
                self.prediction = p
            }
        }
    }
}
