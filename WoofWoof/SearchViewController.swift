//
//  SearchViewController.swift
//  WoofWoof
//
//  Created by Guy on 11/02/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit

class SearchViewController: UITableViewController {
    private var search = UISearchBar(frame: .zero)
    var filtered = Array(Storage.default.allMeals.reversed()) {
        didSet {
            tableView.reloadData()
        }
    }
    var first = true

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
        tableView.keyboardDismissMode = .onDrag
        clearsSelectionOnViewWillAppear = false
        search.scopeButtonTitles = ["Any","Breakfast","Lunch","Dinner","Other"]
        search.showsScopeBar = true
        search.searchBarStyle = .minimal
        search.delegate = self
        if #available(iOS 13.0, *) {
            search.backgroundColor = UIColor.systemBackground
            search.scopeBarBackgroundImage = UIImage.imageWithColor(UIColor.secondarySystemBackground)
        } else {
            search.scopeBarBackgroundImage = UIImage.imageWithColor(.white)
            // Fallback on earlier versions
        }
//        view.tintColor = #colorLiteral(red: 0.1960784346, green: 0.3411764801, blue: 0.1019607857, alpha: 1)
//        search.barTintColor = view.tintColor
        tableView.tableHeaderView = search
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if first {
            tableView.tableHeaderView?.sizeToFit()
            tableView.tableHeaderView?.becomeFirstResponder()
            first = false
        }
    }
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filtered.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "record", for: indexPath) as! RecordCell
        cell.record = filtered[indexPath.row]
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let ctr = storyboard?.instantiateViewController(withIdentifier: "history") as! HistoryViewController
        ctr.displayDay = filtered[indexPath.row].date
        tableView.tableHeaderView?.resignFirstResponder()
        show(ctr, sender: nil)
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        let record = filtered[indexPath.row]
        do {
            tableView.beginUpdates()
            defer {
                tableView.endUpdates()
            }
            _ = try Storage.default.db.write {
                try record.delete($0)
            }
            tableView.deleteRows(at: [indexPath], with: .automatic)
            Storage.default.reloadToday()
            search(string: search.text ?? "", scope: Entry.MealType(rawValue: search.selectedScopeButtonIndex - 1))
        } catch { }
    }


}

extension SearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        search(string: searchText, scope: Entry.MealType(rawValue: searchBar.selectedScopeButtonIndex - 1))
    }

    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        let searchText = searchBar.text ?? ""
        search(string: searchText, scope: Entry.MealType(rawValue: selectedScope - 1))
    }

    func search(string: String, scope: Entry.MealType?) {
        filtered = Array(Storage.default.allMeals.filter {
            if let mealType = scope, $0.type != mealType {
                return false
            }
            if string.isEmpty {
                return true
            }
            return $0.note?.lowercased().contains(string.lowercased()) == true
        }.reversed())
    }
}

class RecordCell: UITableViewCell {
    @IBOutlet var typeLabel: UILabel?
    @IBOutlet var dateLabel: UILabel?
    @IBOutlet var noteLabel: UILabel?
    @IBOutlet var bolusLabel: UILabel?
    var record: Entry! {
        didSet {
            typeLabel?.text = record.type?.name.capitalized
            noteLabel?.text = record.note
            bolusLabel?.text = record.bolus > 0 ? "\(record.bolus)U" : nil
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            dateLabel?.text = "\(record.date.weekDayName) \(formatter.string(from: record.date))"
        }
    }
}
