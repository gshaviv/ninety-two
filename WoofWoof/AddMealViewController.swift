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
    var kind: Meal.Kind?

    var onSelect: ((Meal) -> Void)?
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
        guard let k = Meal.Kind(rawValue: self.picker.selectedRow(inComponent: 2)) else {
            return
        }
        kind = k
        let cd = comp.toDate()
        let when = Storage.default.todayBolus.map { $0.date }.first(where: { abs($0 - cd) < 20.m }) ?? cd
        let meal = Meal(date: when, kind: kind!)

        dismiss(animated: true) {
            self.onSelect?(meal)
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
            picker.selectRow(kind.rawValue, inComponent: 2, animated: false)
        } else {
            switch now.hour {
            case 5...10:
                picker.selectRow(Meal.Kind.breakfast.rawValue, inComponent: 2, animated: false)
            case 11...14:
                picker.selectRow(Meal.Kind.lunch.rawValue, inComponent: 2, animated: false)
            case 18...21:
                picker.selectRow(Meal.Kind.dinner.rawValue, inComponent: 2, animated: false)
            default:
                picker.selectRow(Meal.Kind.other.rawValue, inComponent: 2, animated: false)
            }
        }
        preferredContentSize = CGSize(width: 420, height: view.systemLayoutSizeFitting(CGSize(width: 420, height: 1000)).height)
    }

}

extension AddMealViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 3
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch component {
        case 0:
            return 24

        case 1:
            return 12

        default:
            return 4
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch component {
        case 0:
            return "\(row)"

        case 1:
            return "\(row * 5)"

        default:
            return Meal.Kind(rawValue: row)!.name.capitalized
        }
    }

}
