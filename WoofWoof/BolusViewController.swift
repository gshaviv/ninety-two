//
//  BolusViewController.swift
//  WoofWoof
//
//  Created by Guy on 18/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit

class BolusViewController: ActionSheetController {
    @IBOutlet var picker: UIPickerView!

    var onSelect: ((Date, Int) -> Void)?
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

        dismiss(animated: true) {
            self.onSelect?(comp.date, self.picker.selectedRow(inComponent: 2))
            self.onSelect = nil
            self.onCancel = nil
        }
    }


    override func viewDidLoad() {
        super.viewDidLoad()

        picker.selectRow(Date().hour, inComponent: 0, animated: false)
        picker.selectRow(Int(round(Double(Date().minute) / 5.0)), inComponent: 1, animated: false)
        preferredContentSize = CGSize(width: 420, height: view.systemLayoutSizeFitting(CGSize(width: 420, height: 1000)).height)
    }

}

extension BolusViewController: UIPickerViewDelegate, UIPickerViewDataSource {
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
            return 50
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch component {
        case 0:
            return "\(row)"

        case 1:
            return "\(row * 5)"

        default:
            return "\(row + 1)"
        }
    }

}
