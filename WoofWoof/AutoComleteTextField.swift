//
//  AutoComleteTextField.swift
//  WoofWoof
//
//  Created by Guy on 23/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit

@objc protocol AutoComleteTextFieldDataSource: NSObjectProtocol {
    @objc optional func autocomplete(textField: AutoComleteTextField, text: String) -> [String]
    @objc optional func autocompleteAttributedCompletions(textField: AutoComleteTextField, text: String) -> [NSAttributedString]
}

class AutoComleteTextField: UITextField {
    private var tableView: UITableView?
    @IBOutlet weak var autocompleteDataSource: AutoComleteTextFieldDataSource?
    @IBInspectable var minCharactersForSuggestion: Int = 2
    private let queue = DispatchQueue(label: "autocomplete")
    var addTableView: ((UITableView) -> Void)?
    private var autoCompletions: [String]?
    private var autoAttributedCompletions: [NSAttributedString]?


    override func awakeFromNib() {
        super.awakeFromNib()
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange), name: UITextField.textDidChangeNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(didEndEditing), name: UITextField.textDidEndEditingNotification, object: self)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        awakeFromNib()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    @objc private func textDidChange(_ note:Notification) {
        guard let text = text, text.count > minCharactersForSuggestion, let autocompleteDataSource = self.autocompleteDataSource, note.userInfo?["autocompletion"] == nil else {
            return
        }
        queue.async {
            let attributedWords = autocompleteDataSource.autocompleteAttributedCompletions?(textField: self, text: text)
            let words = attributedWords == nil ? autocompleteDataSource.autocomplete?(textField: self, text: text) : nil
            let isEmpty = attributedWords?.isEmpty ?? words?.isEmpty ?? true

            DispatchQueue.main.async {
                self.autoCompletions = words
                self.autoAttributedCompletions = attributedWords
                if self.tableView == nil && !isEmpty {
                    self.tableView = UITableView(frame: .zero)
                    self.tableView?.translatesAutoresizingMaskIntoConstraints = false
                    guard let tableView = self.tableView else {
                        return
                    }
                    tableView.delegate = self
                    tableView.dataSource = self
                    tableView.rowHeight = UITableView.automaticDimension
                    tableView.estimatedRowHeight = 40
                    if let addTableView = self.addTableView {
                        addTableView(tableView)
                    } else {
                        self.superview?.addSubview(tableView)
                        makeConstraints {
                            tableView[.top] == self[.bottom]
                            tableView[.leading] == self[.leading]
                            tableView[.trailing] == self[.trailing]
                            tableView[.bottom] == self.superview![.bottom] - 20
                        }
                    }
                } else if isEmpty {
                    self.tableView?.removeFromSuperview()
                    self.tableView = nil
                }
                self.tableView?.reloadData()
            }
        }
    }

    @objc private func didEndEditing() {
        tableView?.removeFromSuperview()
        tableView = nil
    }
}


extension AutoComleteTextField: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return autoAttributedCompletions?.count ?? autoCompletions?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
        if let completions = autoAttributedCompletions {
            cell.textLabel?.attributedText = completions[indexPath.row]
        } else if let completions = autoCompletions {
            cell.textLabel?.text = completions[indexPath.row]
        } else {
            cell.textLabel?.text = ""
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        text = autoAttributedCompletions?[indexPath.row].string ?? autoCompletions?[indexPath.row]
        tableView.removeFromSuperview()
        self.tableView = nil
        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: self, userInfo: ["autocompletion": true])
        resignFirstResponder()
    }


}
