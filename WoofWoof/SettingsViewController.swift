//
//  SettingsViewController.swift
//  WoofWoof
//
//  Created by Guy on 26/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit
import WatchConnectivity
import IntentsUI
import Zip
import Sqlable

extension SettingsViewController {
    override func awakeFromNib() {
        super.awakeFromNib()
        addGroup("General")
        if HealthKitManager.isAvailable {
            addBool(title: "Store data in HealthKit", get: { () -> Bool in
                return defaults[.writeHealthKit]
            }) {
                guard HealthKitManager.isAvailable else {
                    logError("HealthKit not available")
                    return
                }
                defaults[.writeHealthKit] = $0
                if $0 {
                    HealthKitManager.authorize({ (granted) in
                        guard granted else {
                            logError("HK permission not granted")
                            return
                        }
                        HealthKitManager.shared?.findLast {
                            let date = $0 ?? Date.distantPast
                            guard let points = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date > date).orderBy(GlucosePoint.date))  else {
                                return
                            }
                            log("last HK record \(date), writng \(points.count) points")
                            HealthKitManager.shared?.write(points: points)
                            
                            let boluses = Storage.default.db.evaluate(Record.read().filter(Record.date > date && Record.bolus > 0).orderBy(Record.date)) ?? []
                            if !boluses.isEmpty {
                                HealthKitManager.shared?.write(records: boluses)
                            }
                        }
                    })
                }
            }
        }
        addEnum("Summary Timeframe", count: UserDefaults.summaryPeriods.count, get: { () -> Int in
            return defaults[.summaryPeriod]
        }, set: {
            defaults[.summaryPeriod] = $0
        }) {
            $0 == 0 ? "24 hours" : "\(UserDefaults.summaryPeriods[$0]) days"
        }
        addValue(title: "Libre days", get: { () -> String in
            "\(defaults[.libreDays])"
        }) {
            defaults[.libreDays] = Int($0)
        }
        
        addGroup("Target Range")
        addValue(title: "Max", get: {
            String(format: "%lg", defaults[.maxRange])
        }) {
            defaults[.maxRange] = $0
        }
        addValue(title: "Min", get: {
            String(format: "%lg", defaults[.minRange])
        }) {
            defaults[.minRange] = $0
        }
        
        addGroup("Alerts")
        addValue(title: "High Level", get: {
            String(format: "%lg", defaults[.highAlertLevel])
        }) {
            defaults[.highAlertLevel] = $0
        }
        addValue(title: "Low Level", get: {
            String(format: "%lg", defaults[.lowAlertLevel])
        }) {
            defaults[.lowAlertLevel] = $0
        }
        addValue(title: "Time to Predicted Low [m]", get: {
            String(format: "%lg", defaults[.timeToLow])
        }) {
            defaults[.timeToLow] = $0
        }
        addBool(title: "Vibrate", get: { () -> Bool in
            return defaults[.alertVibrate]
        }) {
            defaults[.alertVibrate] = $0
        }
        
        addGroup("Insulin (Bolus) Profile")
        addValue(title: "DIA (m)", get: { () -> String in
            return defaults[.diaMinutes] % ".0lf"
        }) {
            if $0 >= 2 * defaults[.peakMinutes] {
                defaults[.diaMinutes] = $0
            }
        }
        addValue(title: "Peak (m)", get: { () -> String in
            return defaults[.peakMinutes] % ".0lf"
        }) {
            if $0 < defaults[.diaMinutes] / 2 {
                defaults[.peakMinutes] = $0
            }
        }
        addValue(title: "Delay (m)", get: { () -> String in
            return defaults[.delayMinutes] % ".0lf"
        }) {
            defaults[.delayMinutes] = $0
        }
        if WCSession.default.isPaired && WCSession.default.isWatchAppInstalled {
            addGroup("Watch Complication Updates")
            addTime(title: "Wakeup time", get: {
                (defaults[.watchWakeupTime] / 60, defaults[.watchWakeupTime] % 60)
            }) {
                defaults[.watchWakeupTime] = $0 * 60 + $1
            }
            addTime(title: "Sleep time", get: {
                (defaults[.watchSleepTime] / 60, defaults[.watchSleepTime] % 60)
            }) {
                defaults[.watchSleepTime] = $0 * 60 + $1
            }
            addGroup("Watch App")
            addEnum("Graph Style", count: 2, get: { () -> Int in
                defaults[.useDarkGraph] ? 1 : 0
            }, set: {
                defaults[.useDarkGraph] = $0 == 1
            }) {
                $0 == 0 ? "Light" : "Dark"
            }
        }
        
        addGroup("Colors")
        addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color5]
        }) {
            defaults[.color5] = $0
        }
        addValue(title: "Value", get: { () -> String in
            defaults[.level4] % "lg"
        }) {
            defaults[.level4] = $0
        }
        addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color4]
        }) {
            defaults[.color4] = $0
        }
        addValue(title: "Value", get: { () -> String in
            defaults[.level3] % "lg"
        }) {
            defaults[.level3] = $0
        }
        addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color3]
        }) {
            defaults[.color3] = $0
        }
        addValue(title: "Value", get: { () -> String in
            defaults[.level2] % "lg"
        }) {
            defaults[.level2] = $0
        }
        addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color2]
        }) {
            defaults[.color2] = $0
        }
        addValue(title: "Value", get: { () -> String in
            defaults[.level1] % "lg"
        }) {
            defaults[.level1] = $0
        }
        addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color1]
        }) {
            defaults[.color1] = $0
        }
        addValue(title: "Value", get: { () -> String in
            defaults[.level0] % "lg"
        }) {
            defaults[.level0] = $0
        }
        addColor(title: "Color", get: { () -> (UIColor) in
            defaults[.color0]
        }) {
            defaults[.color0] = $0
        }
        
        addGroup("Report")
        addBool(title: "Daily Pattern", get: { () -> Bool in
            return defaults[.includePatternReport]
        }) {
            defaults[.includePatternReport] = $0
        }
        addBool(title: "Meal Pattern", get: { () -> Bool in
            return defaults[.includeMealReport]
        }) {
            defaults[.includeMealReport] = $0
        }
        addBool(title: "Daily Logs", get: { () -> Bool in
            return defaults[.includeDailyReport]
        }) {
            defaults[.includeDailyReport] = $0
        }
        
        var siriActions = Set<Record>()
        let group = DispatchGroup()
        group.enter()
        var has = false
        var hasBob = false
        INVoiceShortcutCenter.shared.getAllVoiceShortcuts { (results, _) in
            for voiceShortcut in results ?? [] {
                if let i = voiceShortcut.shortcut.intent as? DiaryIntent {
                    siriActions.insert(i.record)
                } else if voiceShortcut.shortcut.intent is CheckGlucoseIntent {
                    has = true
                } else if voiceShortcut.shortcut.intent is CheckBOBIntent {
                    hasBob = true
                }
            }
            group.leave()
        }
        group.wait()
        
        var entries = [Record: Int]()
        if !siriActions.contains(Record(date: Date.distantFuture, meal: Record.MealType.breakfast)) {
            entries[Record(date: Date.distantFuture, meal: Record.MealType.breakfast)] = 400
        }
        if !siriActions.contains(Record(date: Date.distantFuture, meal: Record.MealType.lunch)) {
            entries[Record(date: Date.distantFuture, meal: Record.MealType.lunch)] = 300
        }
        if !siriActions.contains(Record(date: Date.distantFuture, meal: Record.MealType.dinner)) {
            entries[Record(date: Date.distantFuture, meal: Record.MealType.dinner)] = 200
        }
        if !siriActions.contains(Record(date: Date.distantFuture, meal: Record.MealType.other)) {
            entries[Record(date: Date.distantFuture, meal: Record.MealType.other)] = 100
        }
        Storage.default.allEntries.filter { $0.date > Date() - 1.y }.map { Record(date: Date.distantFuture, meal: $0.type, bolus: $0.bolus, note: $0.note) }.forEach {
            if !siriActions.contains($0) {
                if let count = entries[$0] {
                    entries[$0] = count + 1
                } else {
                    entries[$0] = 1
                }
            }
            if let note = $0.note {
                let r = Record(date: Date.distantFuture, meal: nil, bolus: $0.bolus, note: note)
                if !siriActions.contains(r) {
                    if let count = entries[r] {
                        entries[r] = count + 1
                    } else {
                        entries[r] = 1
                    }
                }
            }
        }
        for key in entries.keys {
            if key.type != nil, let note = key.note {
                let r = Record(date: Date.distantFuture, meal: nil, bolus: key.bolus, note: note)
                if let full = entries[key], let partial = entries[r], partial == full {
                    entries[r] = nil
                } else if siriActions.contains(key) {
                    entries[r] = nil
                }
            }
        }
        let common = entries.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }.filter { $0.1 > 6 }
        if !common.isEmpty || !has || !hasBob {
            let top = common[0 ..< min(common.count, 8)].map { $0.0 }
            addGroup("Add Siri Shortcut")
            if !has {
                addRow(title: "Glucose Measurment", subtitle: "What's my glucose?", configure: {
                    $0.imageView?.image = UIImage(named: "AppIcon")
                    $0.accessoryView = UIImageView(image: UIImage(named: "plus"))
                }) { [weak self] in
                    let intent = CheckGlucoseIntent()
                    intent.suggestedInvocationPhrase = "What's my glucose"
                    if let shortcut = INShortcut(intent: intent) {
                        let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
                        viewController.delegate = self
                        self?.present(viewController, animated: true)
                    }
                }
            }
            if !hasBob {
                addRow(title: "Find my BOB", subtitle: "Any bolus on board?", configure: {
                    $0.imageView?.image = UIImage(named: "AppIcon")
                    $0.accessoryView = UIImageView(image: UIImage(named: "plus"))
                }) { [weak self] in
                    let intent = CheckBOBIntent()
                    intent.suggestedInvocationPhrase = "Any bolus on board?"
                    if let shortcut = INShortcut(intent: intent) {
                        let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
                        viewController.delegate = self
                        self?.present(viewController, animated: true)
                    }
                }
            }
            for record in top {
                addRow(title: record.intent.value(forKey: "title") as? String ?? record.intent.suggestedInvocationPhrase ?? "", subtitle: record.intent.value(forKey: "subtitle") as? String, configure: {
                    $0.imageView?.image = UIImage(named: "AppIcon")
                    $0.accessoryView = UIImageView(image: UIImage(named: "plus"))
                }) { [weak self] in
                    if let shortcut = INShortcut(intent: record.intent) {
                        let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
                        viewController.delegate = self
                        self?.present(viewController, animated: true)
                    }
                }
            }
        }
        
        addGroup("")
        addButton("Backup Database") { [weak self] in
            Storage.default.db.async {
                try? Storage.default.db.execute("vacuum")
                let documentsDirectory = FileManager.default.urls(for:.documentDirectory, in: .userDomainMask)[0]
                let zipFilePath = documentsDirectory.appendingPathComponent("archive.zip")
                let path = Storage.default.dbUrl.path
                let shm = URL(fileURLWithPath: "\(path)-shm")
                let wal = URL(fileURLWithPath: "\(path)-wal")
                try? Zip.zipFiles(paths: [Storage.default.dbUrl, shm, wal], zipFilePath: zipFilePath, password: nil, progress: nil)
                DispatchQueue.main.async {
                    let activityController = UIActivityViewController(activityItems: [zipFilePath], applicationActivities: nil)
                    activityController.excludedActivityTypes = [.postToTwitter, .postToFacebook, .message, .postToWeibo, .print, .copyToPasteboard, .assignToContact]
                    activityController.completionWithItemsHandler = { _,_,_,_ in
                        try? FileManager.default.removeItem(at: zipFilePath)
                    }
                    self?.present(activityController, animated: true, completion: nil)
                }
            }
        }
        addButton("Training Data") { [weak self] in
            DispatchQueue.global().async {
                let all = Storage.default.mealData(includeBolus: true, includeMeal: true)
                let clean = all.filter { $0.iob == 0 && $0.cob == 0 }
                let write = { (data:[Storage.Datum], filename: String) in
                    let content = data.reduce(into: "kind,start,carbs,high,low,end,bolus,iob,cob\n") {
                        $0.append("\($1.kind),\($1.start.decimal(digits:1)),\($1.carbs.decimal(digits: 0)),\($1.high.decimal(digits:1)),\($1.low.decimal(digits:1)),\($1.end.decimal(digits:1)),\($1.bolus),\($1.iob.decimal(digits:2)),\($1.cob.decimal(digits:2))\n")
                    }
                    try? content.write(toFile: filename, atomically: true, encoding: .ascii)
                }
                let tmpDir = NSTemporaryDirectory()
                let allFile = tmpDir.appending(pathComponent: "all.csv")
                write(all, allFile)
                let cFile = tmpDir.appending(pathComponent: "clear.csv")
                write(clean, cFile)
                let zipFile = tmpDir.appending(pathComponent: "csv.zip")
                try? Zip.zipFiles(paths: [URL(fileURLWithPath:allFile), URL(fileURLWithPath:cFile)], zipFilePath: URL(fileURLWithPath:zipFile), password: nil, progress: nil)
                DispatchQueue.main.async {
                    let activityController = UIActivityViewController(activityItems: [URL(fileURLWithPath:zipFile)], applicationActivities: nil)
                    activityController.excludedActivityTypes = [.postToTwitter, .postToFacebook, .message, .postToWeibo, .print, .copyToPasteboard, .assignToContact]
                    activityController.completionWithItemsHandler = { _,_,_,_ in
                        try? FileManager.default.removeItem(at: URL(fileURLWithPath: zipFile))
                        try? FileManager.default.removeItem(at: URL(fileURLWithPath: allFile))
                        try? FileManager.default.removeItem(at: URL(fileURLWithPath: cFile))
                    }
                    self?.present(activityController, animated: true, completion: nil)
                }
            }
        }
        if let old = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date < Date() - 1.y).limit(1)), !old.isEmpty {
            addButton("Delete records older than 1y") { [weak self] in
                do {
                    let timestamp = Int((Date() - 1.y).timeIntervalSince1970)
                    try Storage.default.db.execute("delete from \(GlucosePoint.tableName) where date < \(timestamp)")
                    try Storage.default.db.execute("delete from \(Calibration.tableName) where date < \(timestamp)")
                    try Storage.default.db.execute("delete from \(Record.tableName) where date < \(timestamp)")
                    try Storage.default.db.execute("delete from \(ManualMeasurement.tableName) where date < \(timestamp)")
                    try Storage.default.db.execute("vacuum")
                    let alert = UIAlertController(title: "Done", message: "Deleted records over 1 year old", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: nil))
                    self?.present(alert, animated: true, completion: nil)
                } catch {}
            }
        }
        
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            addGroup("- Version \(v) (\(b))")
        }
    }
}

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
//        if !currentItems.isEmpty {
            grouped.append((currentTitle, currentItems))
//        }
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

extension SettingsViewController: INUIAddVoiceShortcutViewControllerDelegate {
    func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?) {
        if let voiceShortcut = voiceShortcut {
            log("Added \(voiceShortcut)")
        }
        controller.dismiss(animated: true, completion: nil)
    }
    
    func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
        controller.dismiss(animated: true, completion: nil)
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

