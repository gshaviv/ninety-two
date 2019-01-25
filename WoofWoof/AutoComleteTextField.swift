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
    func autocomplete(textField: AutoComleteTextField, text: String) -> [String]
}

class AutoComleteTextField: UITextField {
    private var tableView: UITableView?
    @IBOutlet weak var autocompleteDataSource: AutoComleteTextFieldDataSource?
    @IBInspectable var minCharactersForSuggestion: Int = 2
    private let queue = DispatchQueue(label: "autocomplete")
    var addTableView: ((UITableView) -> Void)?
    private var autoCompletions: [String] = []
    

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
            let words = autocompleteDataSource.autocomplete(textField: self, text: text)

            DispatchQueue.main.async {
                self.autoCompletions = words
                if self.tableView == nil && !words.isEmpty {
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
                } else if words.isEmpty {
                    self.tableView?.removeFromSuperview()
                    self.tableView = nil
                }
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
        return autoCompletions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
        cell.textLabel?.text = autoCompletions[indexPath.row]
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        text = autoCompletions[indexPath.row]
        tableView.removeFromSuperview()
        self.tableView = nil
        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: self, userInfo: ["autocompletion": true])
    }


}
