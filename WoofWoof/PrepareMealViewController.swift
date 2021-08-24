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

protocol PrepareMealViewControllerDelegate: AnyObject {
    func didSelectServing(_ serving: FoodServing)
    func didSelectMeal(_ meal: Meal)
}

class PrepareMealViewController: UITableViewController {
    var foundFood = [Food]()
    var foundMeal = [Meal]()
    let searchController = UISearchController(searchResultsController: nil)
    weak var delegate: PrepareMealViewControllerDelegate?
    var lastTerm = ""

    enum Section: Int {
        case meals
        case food
    }

    override func viewDidLoad() {
        super.viewDidLoad()
//        registerForPreviewing(with: self, sourceView: tableView)
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Food & Meals"
        searchController.searchBar.autocorrectionType = .yes
        searchController.searchBar.spellCheckingType = .yes
        navigationItem.searchController = searchController
        definesPresentationContext = true
        title = "Add Food"
        clearsSelectionOnViewWillAppear = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isMovingToParent {
            searchController.isActive = true
        }
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

    @objc private func accessoryTap(_ sender: UITapGestureRecognizer) {
        let tag = sender.view!.tag
        let ip = IndexPath(row: tag / 2, section: tag % 2)
        tableView(tableView, accessoryButtonTappedForRowWith: ip)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "food") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "food")
        cell.detailTextLabel?.numberOfLines = 3
        cell.textLabel?.numberOfLines = 2
        let button = UILabel(frame: .zero)
        button.text = "Add"
        button.font = UIFont.preferredFont(forTextStyle: .caption2)
//        button.layer.borderColor = UIColor.black.cgColor
//        button.layer.borderWidth = 1
        button.textColor = view.tintColor
        button.sizeToFit()
        let size = button.frame.size
        button.frame.size = CGSize(width: size.width + 16, height: size.height + 8)
        button.isUserInteractionEnabled = true
        button.tag = indexPath.row * 2 + indexPath.section
        button.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(accessoryTap(_:))))
        cell.accessoryView = button
        switch Section(rawValue: indexPath.section)! {
        case .meals:
            let meal = foundMeal[indexPath.row]
            cell.textLabel?.text = meal.name
            cell.detailTextLabel?.text = meal.servings.map {
                let c = $0.food.name.components(separatedBy: ",")
                return (c.count > 1 ? c[1] : c[0]).capitalized
            }.joined(separator: ", ")

        case .food:
            let food = foundFood[indexPath.row]
            cell.textLabel?.text = food.name.capitalized
            cell.detailTextLabel?.text = food.ingredients?.listCase()
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

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .food:
            performSegue(withIdentifier: "amount", sender: foundFood[indexPath.row])
        case .meals:
            delegate?.didSelectMeal(foundMeal[indexPath.row])
            navigationController?.popViewController(animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .food:
            performSegue(withIdentifier: "food", sender: foundFood[indexPath.row])
        case .meals:
            break
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

        case let ctr as FoodViewController:
            guard let food = sender as? Food else {
                return
            }
            ctr.food = food

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

extension PrepareMealViewController: UISearchControllerDelegate {
    func didPresentSearchController(_ searchController: UISearchController) {
        searchController.registerForPreviewing(with: self, sourceView: tableView)
        DispatchQueue.main.async {
            searchController.searchBar.becomeFirstResponder()
        }
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
        if term.hasSuffix("!") {
            return
        }
        if term.hasSuffix(" ") && term.count == lastTerm.count + 1 {
            return
        }
        lastTerm = term
        let anyMeal = (term.isEmpty ? Storage.default.db.evaluate(Meal.read()) : Storage.default.db.evaluate(Meal.read().filter(Meal.name.like("%\(term)%")))) ?? []
        let foundMeal = anyMeal.filter { $0.name != nil && $0.servings.count > 0 }.sorted { $0.name!.lowercased() < $1.name!.lowercased() }
        DispatchQueue.main.async {
            self.foundMeal = foundMeal
            self.tableView.reloadData()
        }
        PrepareMealViewController.searchQueue.async {
            let foundFood:[Food]
            if term.count > 2 {
                let words = term.lowercased().components(separatedBy: " ").filter { !$0.isEmpty }.sorted {
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
                    found = Food.matching(term: words[0])?.filter {
                        for word in words[1...] {
                            switch word.hasPrefix("!") {
                            case false:
                                if !$0.name.lowercased().contains(word) {
                                    return false
                                }

                            case true:
                                if $0.name.lowercased().contains(word[1...]) {
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
            DispatchQueue.main.async {
                self.foundFood = foundFood
                self.tableView.reloadData()
            }
        }
    }
}

extension PrepareMealViewController: UIViewControllerPreviewingDelegate {
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard let indexPath = tableView.indexPathForRow(at: location), indexPath.section == Section.food.rawValue,
            let ctr = storyboard?.instantiateViewController(withIdentifier: "preview") as? FoodViewController else {
            return nil
        }
        ctr.food = foundFood[indexPath.row]
        ctr.origin = self
        return ctr
    }

    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        show(viewControllerToCommit, sender: nil)
    }


}

protocol ServingViewControllerDelegate: AnyObject {
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

    override func viewDidLoad() {
        super.viewDidLoad()
        prompt.text = "How \(food.name.lowercased().hasSuffix("s") ? "many" : "much")  \(food.name.lowercased())?"
        uom.text = food.householdName.capitalized

        let units = Int(food.householdSize)
        picker.selectRow(units, inComponent: Component.unit.rawValue, animated: false)
        let fraction = food.householdSize - Double(units)
        var minIndex = 0
        var minValue = 2.0
        for (idx, value) in Double.fractions.enumerated() {
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
        let amount = Double(picker.selectedRow(inComponent: Component.unit.rawValue)) + Double.fractions[picker.selectedRow(inComponent: Component.fraction.rawValue)].0
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
            if food.householdName.lowercased().hasPrefix("g") {
                return 301
            }
            return 101
        case .fraction:
            return Double.fractions.count
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch Component(rawValue: component)! {
        case .unit:
            return "\(row)"

        case .fraction:
            return Double.fractions[row].1
        }
    }
}
