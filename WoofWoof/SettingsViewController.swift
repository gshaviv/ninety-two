//
//  SettingsViewController.swift
//  WoofWoof
//
//  Created by Guy on 26/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit

class SettingsViewController: UITableViewController {
    private enum Setting {
        case string(String, () -> String, (String) -> Void)
        case time(String, () -> (Int,Int), (Int,Int) -> Void)
        case value(String, () -> String, (Double) -> Void)
        case bool(String, () -> Bool, (Bool) -> Void)
        case color(String, () -> UIColor, (UIColor) -> Void)
        case group(String)
        case button(String, () -> Void)
        case `enum`(String, Int, () -> Int, (Int)-> Void, (Int) -> String)
        case row(String, String?, ((UITableViewCell) -> Void)?, () -> Void)
    }
    private var settings: [Setting] = []
    private var grouped: [(title: String?, items: [Setting])] = []

    public func addRow(title: String, subtitle: String? = nil, configure: ((UITableViewCell) -> Void)? = nil, didSelect: @escaping () -> Void) {
        settings.append(Setting.row(title, subtitle, configure, didSelect))
    }

    public func addValue(title: String, get: @escaping () -> String, set: @escaping (Double) -> Void) {
        settings.append(Setting.value(title, get, set))
    }

    public func addString(title: String, get: @escaping () -> String, set: @escaping (String) -> Void) {
        settings.append(Setting.string(title, get, set))
    }

    public func addBool(title: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) {
        settings.append(Setting.bool(title, get, set))
    }

    public func addTime(title: String, get: @escaping () -> (Int,Int), set: @escaping (Int,Int) -> Void) {
        settings.append(Setting.time(title, get, set))
    }

    public func addColor(title: String, get: @escaping () -> (UIColor), set: @escaping (UIColor) -> Void) {
        settings.append(Setting.color(title, get, set))
    }

    public func addGroup(_ title: String) {
        settings.append(Setting.group(title))
    }

    public func addButton(_ title: String, do: @escaping () -> Void) {
        settings.append(Setting.button(title, `do`))
    }

    public func addEnum(_ title: String, count: Int, get: @escaping () -> Int, set: @escaping (Int) -> Void, values: @escaping (Int) -> String) {
        settings.append(Setting.enum(title, count, get, set, values))
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        grouped = []
        var currentTitle: String? = nil
        var currentItems: [Setting] = []
        for item in settings {
            switch item {
            case let .group(title):
                if !currentItems.isEmpty {
                    grouped.append((currentTitle, currentItems))
                }
                currentTitle = title
                currentItems = []

            default:
                currentItems.append(item)
            }
        }
        if !currentItems.isEmpty {
            grouped.append((currentTitle, currentItems))
        }
        return grouped.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return grouped[section].items.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return grouped[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch grouped[indexPath.section].items[indexPath.row] {
        case let .string(title,get,_):
            let cell = tableView.dequeueReusableCell(withIdentifier: "string") as! StringCell
            cell.titleLabel.text = title
            cell.stringLabel.text = get()
            return cell

        case let .value(title,get,_):
            let cell = tableView.dequeueReusableCell(withIdentifier: "value") as! ValueCell
            cell.titleLabel.text = title
            cell.valueLabel.text = get()
            return cell

        case let .time(title,get,_):
            let cell = tableView.dequeueReusableCell(withIdentifier: "time") as! TimeCell
            cell.titleLabel.text = title
            let (h,m) = get()
            cell.setTime(h, m)
            return cell

        case let .color(title, get, _):
            let cell = tableView.dequeueReusableCell(withIdentifier: "color") as! ColorCell
            cell.titleLabel.text = title
            cell.color = get()
            return cell

        case let .bool(title, get, _):
            let cell = tableView.dequeueReusableCell(withIdentifier: "bool") as! BoolCell
            cell.titleLabel.text = title
            cell.boolSwitch.isOn = get()
            return cell

        case let .button(title, _):
            let cell = tableView.dequeueReusableCell(withIdentifier: "button") as! StringCell
            cell.titleLabel.text = title
            return cell

        case let .enum(title, _, get, _, getValue):
            let cell = tableView.dequeueReusableCell(withIdentifier: "string") as! StringCell
            cell.titleLabel.text = title
            cell.stringLabel.text = getValue(get())
            return cell

        case let .row(title, subtitle, configure, _):
            let cell = tableView.dequeueReusableCell(withIdentifier: "row") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "row")
            cell.accessoryType = .disclosureIndicator
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = subtitle
            cell.textLabel?.numberOfLines = 0
            cell.detailTextLabel?.numberOfLines = 0
            configure?(cell)
            return cell

        case .group(_):
            fatalError()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let groupTitle = grouped[indexPath.section].title
        switch grouped[indexPath.section].items[indexPath.row] {
        case let .string(title,get,set):
            let ctr = storyboard?.instantiateViewController(withIdentifier: "string") as! StringViewController
            ctr.title = groupTitle
            ctr.prompt = title
            ctr.value = get()
            ctr.setter = {
                set($0)
                self.tableView.reloadData()
            }
            present(ctr, animated: true, completion: nil)

        case let .value(title,get,set):
            let ctr = storyboard?.instantiateViewController(withIdentifier: "value") as! ValueViewController
            ctr.title = groupTitle
            ctr.prompt = title
            ctr.value = get()
            ctr.setter = {
                set($0)
                self.tableView.reloadData()
            }
            present(ctr, animated: true, completion: nil)

        case let .bool(_,get,set):
            set(!get())
            tableView.reloadData()

        case let .time(title,get,set):
            let ctr = storyboard?.instantiateViewController(withIdentifier: "time") as! TimeViewController
            ctr.title = title
            ctr.value = get()
            ctr.setter = {
                set($0, $1)
                self.tableView.reloadData()
            }
            present(ctr, animated: true, completion: nil)

        case let .color(title, get, set):
            let ctr = storyboard?.instantiateViewController(withIdentifier: "color") as! ColorViewController
            ctr.title = title
            ctr.value = get()
            ctr.setter = {
                set($0)
                self.tableView.reloadData()
            }
            present(ctr, animated: true, completion: nil)

        case let .button(_, handler):
            handler()
            tableView.reloadData()

        case let .enum(title, count, get, set, values):
            let ctr = storyboard?.instantiateViewController(withIdentifier: "enum") as! EnumViewController
            ctr.count = count
            ctr.title = title
            ctr.value = get()
            ctr.setter = {
                set($0)
                self.tableView.reloadData()
            }
            ctr.getValue = values
            present(ctr, animated: true, completion: nil)

        case let .row(_,_,_,didSelect):
            didSelect()

        case .group(_):
            break
        }
    }
}

class StringCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var stringLabel: UILabel!
}

class ValueCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var valueLabel: UILabel!
}

class TimeCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var timeLabel: UILabel!

    func setTime(_ mh: Int) {
        timeLabel.text = "{}:{}".format(mh / 60, (mh % 60) % "02ld")
    }

    func setTime(_ h: Int, _ m:Int) {
        timeLabel.text = "{}:{}".format(h, m % "02ld")
    }
}

class BoolCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var boolSwitch: UISwitch!
}

class ColorCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var colorWell: UIView!

    var color: UIColor {
        set {
            colorWell.backgroundColor = newValue
        }
        get {
            return colorWell.backgroundColor ?? UIColor.white
        }
    }
}


class StringViewController: ActionSheetController {
    @IBOutlet private var mainStackView: UIStackView!
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var promptLabel: UILabel!
    @IBOutlet private var textField: UITextField!

    var prompt: String?
    var value: String?
    var setter: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = title
        promptLabel.text = prompt
        textField.text = value
        preferredContentSize = mainStackView.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width, height: 0), withHorizontalFittingPriority: UILayoutPriority.fittingSizeLevel, verticalFittingPriority: UILayoutPriority.fittingSizeLevel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        textField.becomeFirstResponder()
    }

    @IBAction func handleCancel() {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func handleSave() {
        if let text = textField.text {
            setter?(text)
            setter = nil
        }
        dismiss(animated: true, completion: nil)
    }
}

class ValueViewController: ActionSheetController {
    @IBOutlet private var mainStackView: UIStackView!
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var promptLabel: UILabel!
    @IBOutlet private var textField: UITextField!

    var prompt: String?
    var value: String?
    var setter: ((Double) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = title
        promptLabel.text = prompt
        textField.text = value
        preferredContentSize = mainStackView.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width, height: 0), withHorizontalFittingPriority: UILayoutPriority.required, verticalFittingPriority: UILayoutPriority.fittingSizeLevel)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    @IBAction func handleCancel() {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func handleSave() {
        if let text = textField.text, let v = Double(text) {
            setter?(v)
            setter = nil
         }
        dismiss(animated: true, completion: nil)
    }
}

class TimeViewController: ActionSheetController, UIPickerViewDelegate, UIPickerViewDataSource {
    @IBOutlet private var mainStackView: UIStackView!
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var picker: UIPickerView!

    var value: (Int,Int)!
    var setter: ((Int,Int) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = title
        picker.selectRow(value.0, inComponent: 0, animated: false)
        picker.selectRow(value.1, inComponent: 1, animated: false)
        preferredContentSize = mainStackView.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width, height: 0), withHorizontalFittingPriority: UILayoutPriority.required, verticalFittingPriority: UILayoutPriority.fittingSizeLevel)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    @IBAction func handleCancel() {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func handleSave() {
        setter?(picker.selectedRow(inComponent: 0), picker.selectedRow(inComponent: 1))
        setter = nil
        dismiss(animated: true, completion: nil)
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 2
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch component {
        case 0:
            return 24

        case 1:
            return 60

        default:
            return 0
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return "\(row)"
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        return 40
    }
}

class EnumViewController: ActionSheetController, UIPickerViewDelegate, UIPickerViewDataSource {
    @IBOutlet private var mainStackView: UIStackView!
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var picker: UIPickerView!

    var value: Int!
    var setter: ((Int) -> Void)?
    var getValue: ((Int) -> String)?
    var count: Int!

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = title
        picker.selectRow(value, inComponent: 0, animated: false)
        preferredContentSize = mainStackView.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width, height: 0), withHorizontalFittingPriority: UILayoutPriority.required, verticalFittingPriority: UILayoutPriority.fittingSizeLevel)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    @IBAction func handleCancel() {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func handleSave() {
        setter?(picker.selectedRow(inComponent: 0))
        setter = nil
        dismiss(animated: true, completion: nil)
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return getValue?(row) ?? ""
    }
}


class ColorViewController: ActionSheetController {
    @IBOutlet private var mainStackView: UIStackView!
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var colorPicker: EFHSBView!

    var value: UIColor?
    var setter: ((UIColor) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = title
        colorPicker.color = value ?? .white
        preferredContentSize = mainStackView.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width, height: 0), withHorizontalFittingPriority: UILayoutPriority.required, verticalFittingPriority: UILayoutPriority.fittingSizeLevel)
    }


    @IBAction func handleCancel() {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func handleSave() {
            setter?(colorPicker.color)
            setter = nil
        dismiss(animated: true, completion: nil)
    }
}

