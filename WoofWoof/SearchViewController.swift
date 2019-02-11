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
    var filtered = Storage.default.allMeals {
        didSet {
            tableView.reloadData()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))

        let search = UISearchBar(frame: .zero)
        search.scopeButtonTitles = ["Any","Breakfast","Lunch","Dinner","Other"]
        search.showsScopeBar = true
        search.searchBarStyle = .minimal
        search.scopeBarBackgroundImage = UIImage.imageWithColor(.white)
        search.delegate = self
        tableView.tableHeaderView = search
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.tableHeaderView?.sizeToFit()
        tableView.tableHeaderView?.becomeFirstResponder()
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
        show(ctr, sender: nil)
    }
}

extension SearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        search(string: searchText, scope: Record.Meal(rawValue: searchBar.selectedScopeButtonIndex - 1))
    }

    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        let searchText = searchBar.text ?? ""
        search(string: searchText, scope: Record.Meal(rawValue: selectedScope - 1))
    }

    func search(string: String, scope: Record.Meal?) {
        filtered = Storage.default.allMeals.filter {
            if let mealType = scope, $0.meal != mealType {
                return false
            }
            return $0.note?.lowercased().contains(string.lowercased()) == true
        }
    }
}

class RecordCell: UITableViewCell {
    @IBOutlet var typeLabel: UILabel?
    @IBOutlet var dateLabel: UILabel?
    @IBOutlet var noteLabel: UILabel?
    @IBOutlet var bolusLabel: UILabel?
    var record: Record! {
        didSet {
            typeLabel?.text = record.meal?.name.capitalized
            noteLabel?.text = record.note
            bolusLabel?.text = record.bolus > 0 ? "\(record.bolus)U" : nil
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let daysOfWeek = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            dateLabel?.text = "\(daysOfWeek[record.date.weekDay - 1]) \(formatter.string(from: record.date))"
        }
    }
}
