//
//  AddMealViewController.swift
//  WoofWoof
//
//  Created by Guy on 18/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit

class AddMealViewController: ActionSheetController {
    @IBOutlet var picker: UIPickerView!
    @IBOutlet var noteField: UITextField!
    var kind: Record.Meal?
    var units: Int?
    private enum Component: Int {
        case hour
        case minute
        case meal
        case units
    }

    var onSelect: ((inout Record) -> Void)?
    var onCancel: (() -> Void)?

    @IBAction func handleCancel(_ sender: Any) {
        onSelect = nil
        dismiss(animated: true) {
            self.onCancel?()
            self.onCancel = nil
        }
    }

    @IBAction func handleSelect(_ sender: Any) {
        var comp = Date().components
        comp.hour = picker.selectedRow(inComponent: 0)
        comp.minute = picker.selectedRow(inComponent: 1) * 5
        comp.second = 0
        guard let k = Record.Meal(rawValue: self.picker.selectedRow(inComponent: 2)) else {
            return
        }
        kind = k
        let u = picker.selectedRow(inComponent: Component.units.rawValue)
        if u > 0 {
            units = u
        }
        let cd = comp.toDate()
        var record = Storage.default.lastDay.entries.first(where: { $0.date == cd }) ?? Record(date: cd, meal: nil, bolus: nil, note: nil)
        record.meal = kind
        record.bolus = units
        if let note = noteField.text, !note.isEmpty {
            record.note = note
        }

        dismiss(animated: true) {
            self.onSelect?(&record)
            self.onSelect = nil
            self.onCancel = nil
        }
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

        picker.selectRow(now.hour, inComponent: 0, animated: false)
        picker.selectRow(Int(round(Double(now.minute) / 5.0)), inComponent: 1, animated: false)
        if let kind = kind {
            picker.selectRow(kind.rawValue + 1, inComponent: 2, animated: false)
        } else {
            switch now.hour {
            case 5...10:
                picker.selectRow(Record.Meal.breakfast.rawValue + 1, inComponent: 2, animated: false)
            case 11...14:
                picker.selectRow(Record.Meal.lunch.rawValue + 1, inComponent: 2, animated: false)
            case 18...21:
                picker.selectRow(Record.Meal.dinner.rawValue + 1, inComponent: 2, animated: false)
            default:
                picker.selectRow(Record.Meal.other.rawValue + 1, inComponent: 2, animated: false)
            }
        }
        if let units = units {
            picker.selectRow(units, inComponent: 3, animated: false)
        }
        preferredContentSize = CGSize(width: 420, height: view.systemLayoutSizeFitting(CGSize(width: 420, height: 1000)).height)
    }

}

extension AddMealViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 4
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch component {
        case 0:
            return 24

        case 1:
            return 12

        case 2:
            return 5

        case 3:
            return 50

        default:
            return 0
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch component {
        case 0:
            return "\(row)"

        case 1:
            return "\(row * 5)"

        case 2:
            return Record.Meal(rawValue: row - 1)?.name.capitalized ?? "None"

        case 3:
            return "\(row)"

        default:
            return nil
        }
    }

}
