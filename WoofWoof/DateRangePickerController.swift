//
//  DateRangePickerController.swift
//  WoofWoof
//
//  Created by Guy on 12/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit

class DateRangePickerController: ActionSheetController {
    @IBOutlet var picker: UIPickerView!
    let values = [
        ("Last week", 7.d),
        ("Last two weeks", 14.d),
        ("Last month", 30.d),
        ("Last two months", 60.d),
        ("Last three months", 90.d),
        ("Custom...", 0)
    ]
    var onSelect: ((TimeInterval) -> Void)?
    var onCancel: (() -> Void)?

    @IBAction func handleCancel(_ sender: Any) {
        onSelect = nil
        dismiss(animated: true) {
            self.onCancel?()
            self.onCancel = nil
        }
    }

    @IBAction func handleSelect(_ sender: Any) {
        let selected = values[picker.selectedRow(inComponent: 0)].1
        dismiss(animated: true) {
            self.onSelect?(selected)
            self.onSelect = nil
            self.onCancel = nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 420, height: view.systemLayoutSizeFitting(CGSize(width: 420, height: 1000)).height)
    }


}

extension DateRangePickerController: UIPickerViewDelegate, UIPickerViewDataSource {

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return values.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return values[row].0
    }
}


class DateFromToPickerController: ActionSheetController {
    @IBOutlet var fromPicker: UIDatePicker!
    @IBOutlet var toPicker: UIDatePicker!
    var onSelect: ((Date,Date) -> Void)?
    var onCancel: (() -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 420, height: view.systemLayoutSizeFitting(CGSize(width: 420, height: 1000)).height)
    }

    @IBAction func handleCancel(_ sender: Any) {
        onSelect = nil
        dismiss(animated: true) {
            self.onCancel?()
            self.onCancel = nil
        }
    }

    @IBAction func handleSelect(_ sender: Any) {
        let from = fromPicker.date
        let to = toPicker.date 
        dismiss(animated: true) {
            self.onSelect?(from, to)
            self.onSelect = nil
            self.onCancel = nil
        }
    }
}
