//
//  PrepareMealViewController.swift
//  WoofWoof
//
//  Created by Guy on 16/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit
import Sqlable

protocol PrepareMealViewControllerDelegate: class {
    func didSelectServing(_ serving: FoodServing)
    func didSelectMeal(_ meal: Meal)
}

class PrepareMealViewController: UITableViewController {
    var foundFood = [Food]()
    var foundMeal = [Meal]()
    let searchController = UISearchController(searchResultsController: nil)
    weak var delegate: PrepareMealViewControllerDelegate?

    enum Section: Int {
        case meals
        case food
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Food & Meals"
        navigationItem.searchController = searchController
        definesPresentationContext = true
        title = "Add Food"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.isActive = true
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        switch Section(rawValue: section)! {
        case .meals:
            return foundMeal.count
        case .food:
            return foundFood.count
        }
    }


    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "food") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "food")
        cell.detailTextLabel?.numberOfLines = 3
        cell.textLabel?.numberOfLines = 2
        switch Section(rawValue: indexPath.section)! {
        case .meals:
            let meal = foundMeal[indexPath.row]
            cell.textLabel?.text = meal.name
            cell.detailTextLabel?.text = meal.servings.map { $0.food.name.capitalized }.joined(separator: ", ")

        case .food:
            let food = foundFood[indexPath.row]
            cell.textLabel?.text = food.name.capitalized
            cell.detailTextLabel?.text = food.ingredients
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .meals:
            return foundMeal.isEmpty ? nil : "Meals"
        case .food:
            return foundFood.isEmpty ? nil : "Food"
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .food:
            performSegue(withIdentifier: "amount", sender: foundFood[indexPath.row])
        case .meals:
            delegate?.didSelectMeal(foundMeal[indexPath.row])
            navigationController?.popViewController(animated: true)
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.destination {
        case let ctr as ServingViewController:
            guard let food = sender as? Food else {
                return
            }
            ctr.food = food
            ctr.delegate = self
        default:
            break
        }
    }

}

extension PrepareMealViewController: ServingViewControllerDelegate {
    func didSelectAmount(_ amount: Double, from: Food) {
        let serving = FoodServing(id: from.id, amount: amount, mealId: nil)
        delegate?.didSelectServing(serving)
        navigationController?.popViewController(animated: true)
    }
}


extension PrepareMealViewController: UISearchResultsUpdating {
    static let searchQueue = DispatchQueue(label: "search")
    func updateSearchResults(for searchController: UISearchController) {
        guard let term = searchController.searchBar.text else {
            foundFood = []
            foundMeal = []
            tableView.reloadData()
            return
        }
        if term.hasSuffix(" ") || term.hasSuffix("!") {
            return
        }
        PrepareMealViewController.searchQueue.async {
            let foundFood:[Food]
            if term.count > 3 {
                let words = term.components(separatedBy: " ").filter { !$0.isEmpty }.sorted {
                    switch ($0.hasPrefix("!"), $1.hasPrefix("!")) {
                    case (false, false):
                        return $0.count > $1.count

                    case (true, true):
                        return $0.count < $1.count

                    case (true, false):
                        return false

                    case (false, true):
                        return true
                    }
                }
                let found: [Food]?
                if words.count == 1 {
                    found = Food.matching(term: words[0])
                } else {
                    found = Food.matching(term: words[0])?.filter { (check) in
                        for word in words[1...] {
                            switch word.hasPrefix("!") {
                            case false:
                                if !check.name.lowercased().contains(word) {
                                    return false
                                }

                            case true:
                                if check.name.lowercased().contains(word[1...]) {
                                    return false
                                }
                            }

                        }
                        return true
                    }
                }
                foundFood = found?.sorted { ($0.ingredients?.count ?? 0) < ($1.ingredients?.count ?? 0) } ?? []
            } else {
                foundFood = []
            }
            let foundMeal = (term.isEmpty ? Storage.default.db.evaluate(Meal.read()) : Storage.default.db.evaluate(Meal.read().filter(Meal.name.like("%\(term)%")))) ?? []
            DispatchQueue.main.async {
                self.foundFood = foundFood
                self.foundMeal = foundMeal
                self.tableView.reloadData()
            }
        }
    }
}

protocol ServingViewControllerDelegate: class {
    func didSelectAmount(_ amount: Double, from: Food)
}

class ServingViewController: ActionSheetController {
    var food: Food!
    @IBOutlet var prompt: UILabel!
    @IBOutlet var uom: UILabel!
    @IBOutlet var picker: UIPickerView!
    @IBOutlet var mainStackView: UIView!
    weak var delegate: ServingViewControllerDelegate?
    enum Component: Int {
        case unit
        case fraction
    }
    private var fractions = [
        (0.0,""),(0.1, "⅒"),(0.125,"⅛"),(0.167,"⅙"),
        (0.2, "⅕"),(0.25,"¼"),(0.333,"⅓"),
        (0.375,"⅜"),(0.4,"⅖"),(0.5,"½"),
        (0.6,"⅗"),(0.625,"⅝"),(0.667,"⅔"),(0.75,"¾"),
        (0.8,"⅘"),(0.833,"⅚"),(0.875,"⅞")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        prompt.text = "How \(food.name.lowercased().hasSuffix("s") ? "many" : "much")  \(food.name.lowercased())?"
        uom.text = food.householdName.capitalized

        let units = Int(food.householdSize)
        picker.selectRow(units, inComponent: Component.unit.rawValue, animated: false)
        let fraction = food.householdSize - Double(units)
        var minIndex = 0
        var minValue = 2.0
        for (idx, value) in fractions.enumerated() {
            if abs(value.0 - fraction) < minValue {
                minIndex = idx
                minValue = abs(value.0 - fraction)
            }
        }
        picker.selectRow(minIndex, inComponent: Component.fraction.rawValue, animated: false)
        preferredContentSize = mainStackView.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width, height: 0), withHorizontalFittingPriority: UILayoutPriority.required, verticalFittingPriority: UILayoutPriority.fittingSizeLevel)

    }

    @IBAction func handleCancel(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func handleSelect(_ sender: Any) {
        let amount = Double(picker.selectedRow(inComponent: Component.unit.rawValue)) + fractions[picker.selectedRow(inComponent: Component.fraction.rawValue)].0
        dismiss(animated: true) {
            self.delegate?.didSelectAmount(amount, from: self.food)
        }
    }
}

extension ServingViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 2
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch Component(rawValue: component)! {
        case .unit:
            return 100
        case .fraction:
            return fractions.count
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch Component(rawValue: component)! {
        case .unit:
            return "\(row)"

        case .fraction:
            return fractions[row].1
        }
    }
}
