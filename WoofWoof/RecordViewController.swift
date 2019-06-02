//
//  RecordViewController.swift
//  WoofWoof
//
//  Created by Guy on 16/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import UIKit
import WoofKit
import Sqlable

class RecordViewController: UIViewController {
    @IBOutlet var picker: UIPickerView!
    @IBOutlet var noteField: AutoComleteTextField!
    @IBOutlet var predictionLabel: UILabel!
    @IBOutlet var mealTable: UITableView!
    @IBOutlet var mealHeader: UILabel!
    @IBOutlet var deleteButton: UIBarButtonItem!
    private var prediction: Prediction?
    var onSelect: ((Record, Prediction?) -> Void)?
    var onCancel: (() -> Void)?
    private let queue = DispatchQueue(label: "predict")
    var meal = Meal(name: nil)
    var editRecord: Record? {
        didSet {
            if let meal = editRecord?.meal {
                self.meal = meal
            }
            title = editRecord == nil ? "Add Record" : "Edit Record"
        }
    }
    private lazy var iob: Double = editRecord?.insulinOnBoardAtStart ?? Storage.default.insulinOnBoard(at: Date())

    private enum Component: Int {
        case hour
        case minute
        case meal
        case units
    }
    var selectedDate: Date {
        var comp = Date().components
        comp.hour = picker.selectedRow(inComponent: Component.hour.rawValue)
        comp.minute = picker.selectedRow(inComponent: Component.minute.rawValue)
        comp.second = 0
        return comp.toDate()
    }
    private var sensitivity = Calculation {
        return Storage.default.estimateInsulinReaction()
    }
    private lazy var mealNotes: [NSAttributedString] = {
        let fromMeals = Storage.default.allMeals.compactMap { $0.note }.unique().sorted()
        let setFromMeals = Set(fromMeals)
        let additionalWords = words.filter { !setFromMeals.contains($0) }.sorted()
        return fromMeals.map { $0.styled.traits(.traitBold) } + additionalWords.map { $0.styled }
    }()
    private lazy var words: [String] = {
        let all = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: Bundle(for: Storage.self).path(forResource: "words", ofType: "json")!)), options: []) as! [String: Any]
        var wordList: [String] = []
        for (_,value) in all {
            if let list = value as? [String] {
                wordList += list.map { $0.capitalized }
            }
        }
        return wordList.sorted()
    }()
    var selectedRecord: Record {
        let cd = selectedDate
        let record = editRecord ?? Storage.default.lastDay.entries.first(where: { $0.date == cd }) ?? Record(date: cd, meal: nil, bolus: nil, note: nil)
        record.type = Record.MealType(rawValue: self.picker.selectedRow(inComponent: Component.meal.rawValue) - 1)
        record.bolus = picker.selectedRow(inComponent: Component.units.rawValue)
        record.carbs = meal.totalCarbs
        if let note = noteField.text {
            record.note = note.trimmed.isEmpty ? nil : note.trimmed
            if meal.id == nil {
                meal.name = record.note
            }
        } 

        return record
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        noteField.resignFirstResponder()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setPrediction(nil)
        noteField.text = meal.name
        var now = Date()
        if now.minute > 58 {
            var comp = now.components
            comp.minute = 0
            comp.hour = now.hour + 1
            now = comp.toDate()
        }
        if let edit = editRecord {
            now = edit.date
            deleteButton.isEnabled = true
        } else {
            deleteButton.isEnabled = false
        }
        noteField.text = editRecord?.note
        picker.selectRow(now.hour, inComponent: Component.hour.rawValue, animated: false)
        picker.selectRow(Int(round(Double(now.minute))), inComponent: Component.minute.rawValue, animated: false)
        if let kind = editRecord?.type {
            picker.selectRow(kind.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
        } else {
            switch now.hour {
            case 5...10:
                picker.selectRow(Record.MealType.breakfast.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
            case 11...14:
                picker.selectRow(Record.MealType.lunch.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
            case 18...21:
                picker.selectRow(Record.MealType.dinner.rawValue + 1, inComponent: Component.meal.rawValue, animated: false)
            default:
                picker.selectRow(0, inComponent: Component.meal.rawValue, animated: false)
                picker.selectRow(1, inComponent: Component.units.rawValue, animated: false)
            }
        }
        if let units = editRecord?.bolus {
            picker.selectRow(units, inComponent: Component.units.rawValue, animated: false)
        }
        DispatchQueue.global().async {
            RecordViewController.estimate3()
        }
    }

    @IBAction func handleCancel(_ sender: Any) {
        onSelect = nil
        dismiss(animated: true) {
            self.onCancel?()
            self.onCancel = nil
        }
    }

    @IBAction func handleDelete() {
        onSelect = nil
        if let edit = editRecord {
            edit.discard()
            Storage.default.reloadToday()
        }
        dismiss(animated: true) {
            self.onCancel?()
            self.onCancel = nil
        }
    }

    @IBAction func handleSave() {
        let record = selectedRecord
        if record.isMeal {
            if meal.id == nil {
                try! meal.save()
            }
            if let mealId = record.mealId, mealId != meal.id {
                if let records = Storage.default.db.evaluate(Record.read().filter(Record.mealId == mealId)), records.count == 1 {
                    record.meal.discard(db: Storage.default.db)
                }
            }
            record.mealId = meal.id
        }
        record.save(to: Storage.default.db)
        onCancel = nil
        dismiss(animated: true) {
            self.onSelect?(record, self.prediction)
            self.onSelect = nil
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.destination {
        case let ctr as PrepareMealViewController:
            ctr.delegate = self

        default:
            break
        }
    }
}

extension RecordViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 4
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch Component(rawValue: component)! {
        case .hour:
            return 24

        case .minute:
            return 60

        case .meal:
            return 5

        case .units:
            return 50
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch Component(rawValue: component)! {
        case .hour:
            return "\(row)"

        case .minute:
            return "\(row)"

        case .meal:
            return Record.MealType(rawValue: row - 1)?.name.capitalized ?? "Bolus"

        case .units:
            return "\(row)"
        }
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView.selectedRow(inComponent: Component.meal.rawValue) == 0 && pickerView.selectedRow(inComponent: Component.units.rawValue) == 0 {
            pickerView.selectRow(1, inComponent: Component.units.rawValue, animated: true)
        }
        predict()
        if let rec = editRecord {
            switch Component(rawValue: component)! {
            case .hour, .minute:
                var comp = rec.date.components
                comp.hour = pickerView.selectedRow(inComponent: Component.hour.rawValue)
                comp.minute = picker.selectedRow(inComponent: Component.minute.rawValue)
                editRecord?.date = comp.toDate()

            case .units:
                editRecord?.bolus = picker.selectedRow(inComponent: Component.units.rawValue)

            case .meal:
                guard let k = Record.MealType(rawValue: self.picker.selectedRow(inComponent: Component.meal.rawValue) - 1) else {
                    return
                }
                editRecord?.type = k
            }
        }
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        switch Component(rawValue: component)! {
        case .hour:
            return 40

        case .minute:
            return 40

        case .meal:
            return 180

        case .units:
            return 40
        }
    }
}

extension RecordViewController: UITextFieldDelegate {
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        predict()
        return true
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}


extension RecordViewController: AutoComleteTextFieldDataSource {
    func autocompleteAttributedCompletions(textField: AutoComleteTextField, text: String) -> [NSAttributedString] {
        let lower = text.lowercased()
        return picker.selectedRow(inComponent: Component.meal.rawValue) == 0 ? [] : mealNotes.filter { $0.string.lowercased().hasPrefix(lower) }
    }
}



extension RecordViewController: PrepareMealViewControllerDelegate {
    func didSelectMeal(_ selectedMeal: Meal) {
        if meal.id == nil {
            if meal.servingCount == 0 {
                meal = selectedMeal
                noteField.text = meal.name
            } else {
                selectedMeal.servings.forEach {
                    meal.append($0)
                }
            }
        } else {
            let appendedMeal = Meal(name: noteField.text)
            meal.servings.forEach {
                appendedMeal.append($0)
            }
            selectedMeal.servings.forEach {
                appendedMeal.append($0)
            }
            meal = appendedMeal
        }
        mealTable.reloadData()
        predict()
    }

    func didSelectServing(_ serving: FoodServing) {
        if meal.id != nil {
            let appendedMeal = Meal(name: noteField.text)
            meal.servings.forEach {
                appendedMeal.append($0)
            }
            meal = appendedMeal
        }
        meal.append(serving)
        mealTable.reloadData()
        predict()
    }

}

extension RecordViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        mealHeader.text = "Carbs: \(meal.totalCarbs % ".0lf")g"
        return meal.servingCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "serving") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "serving")
        let serving = meal[indexPath.row]
        cell.textLabel?.text = serving.food.name.capitalized
        cell.textLabel?.numberOfLines = 2
        cell.detailTextLabel?.text = "\(serving.carbs % ".0lf")g: \(serving.amount.asFraction()) \(serving.food.householdName.lowercased())"
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        tableView.beginUpdates()
        tableView.deleteRows(at: [indexPath], with: .automatic)
        if meal.id != nil {
            let appendedMeal = Meal(name: noteField.text)
            meal.servings.enumerated().forEach {
                guard $0.offset != indexPath.row else {
                    return
                }
                appendedMeal.append($0.element)
            }
            meal = appendedMeal
        } else {
            meal.remove(servingAt: indexPath.row)
        }
        tableView.endUpdates()
    }
}

extension RecordViewController {
    func setPrediction(_ str: String?) {
        if let str = str {
            predictionLabel.text = str
            predictionLabel.alpha = 1
        } else if defaults[.parameterCalcDate] != nil, let current = MiaoMiao.currentGlucose?.value, let calculated = Storage.default.calculatedLevel(for: selectedRecord, currentLevel: current) {
            let when = calculated.highDate
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short

            predictionLabel.text = "Current \(current % ".0lf"), BOB \(selectedRecord.insulinOnBoardAtStart % ".1lf")\nEstimate \(Int(calculated.h50)) @ \(formatter.string(from: when))\n\(Int(calculated.h10)) - \(Int(calculated.h90))"
            predictionLabel.alpha = 1
            self.prediction = calculated
        } else {
            predictionLabel.text = "Current BG: \((MiaoMiao.currentGlucose?.value ?? 0) % ".0lf")\nBOB=\(iob % ".1lf")\n"
            if iob > 0 {
                predictionLabel.text = "BOB = \(iob % ".1lf")U\n\n"
            }
            predictionLabel.alpha = 0.5
            self.prediction = nil
        }
    }

    @objc func predict() {
        if picker.selectedRow(inComponent: Component.meal.rawValue) == 0 {
                setPrediction(nil)
            return
        }
        let record = selectedRecord
        queue.async {
            guard let p = Storage.default.prediction(for: record) else {
                DispatchQueue.main.async {
                    self.setPrediction(nil)
                }
                return
            }
            DispatchQueue.main.async {
                if p.h50 < p.h90  && p.low50 > p.low {
                    self.setPrediction("Estimate using \(p.mealCount) similar meals\nHigh: 50%=\(p.h50), 90%<\(p.h90)\nLow: 90%>\(p.low), 50%=\(p.low50)")
                } else if p.h50 < p.h90 {
                    self.setPrediction("Estimate using \(p.mealCount) similar meals\nHigh: 50%=\(p.h50), 90%<\(p.h90)\nLow: 90%>\(p.low)")
                } else {
                    self.setPrediction("Estimate using \(p.mealCount) similar meals\n@\(String(format: "%02ld:%02ld",p.highDate.hour, p.highDate.minute)): 50%=\(p.h50)\nLow: \(p.low)")
                }
                self.prediction = p
            }
        }
    }
}

extension RecordViewController {
    struct MealEffect {
        let change: Double
        let carbs: Double
        let units: Double
        let slope: Double
        let length: TimeInterval
    }
    static func getEffects() -> [MealEffect] {
        let meals = Array(Storage.default.allEntries.filter { $0.mealId != nil || $0.isBolus }.reversed())
        let after = (defaults[.diaMinutes] + defaults[.delayMinutes]) * 60
        var effects = [MealEffect]()
        guard let bgHistory = Storage.default.db.evaluate(GlucosePoint.read().orderBy(GlucosePoint.date))?.map({ CGPoint(x: $0.date.timeIntervalSince1970, y: $0.value)}) else {
            return []
        }
        let interpolator = AkimaInterpolator(points: bgHistory)
        for meal in meals {
            var horizon = meal.date + after
            let carbs: Double
            let units: Double
            let bgAfter: CGFloat
            if let _ = Storage.default.allEntries.filter({ $0.date < horizon && $0.date > meal.date - after && $0.id! != meal.id!  }).first {
                continue
            }
            if let low = Storage.default.db.evaluate(GlucosePoint.read().filter(GlucosePoint.date < horizon && GlucosePoint.date > meal.date && GlucosePoint.value < 70)), !low.isEmpty {
                horizon = Date(timeInterval: -10.m, since: low.first!.date)
                let ratio = (horizon - meal.date) / after
                units = Double(meal.bolus) - meal.insulinAction(at: horizon).iob
                carbs = meal.carbs * ratio
                bgAfter = interpolator.interpolateValue(at: CGFloat(horizon.timeIntervalSince1970))
            } else {
                units = Double(meal.bolus)
                carbs = meal.carbs
                bgAfter = interpolator.interpolateValue(at: CGFloat(horizon.timeIntervalSince1970))
            }
            let bgAtMeal = interpolator.interpolateValue(at: CGFloat(meal.date.timeIntervalSince1970))
            guard !bgAfter.isNaN && !bgAtMeal.isNaN else {
                continue
            }
            var sum = CGFloat(0)
            var count = 0
            for duration in [15.m, 30.m, 45.m, 1.h] {
                if Storage.default.insulinOnBoard(at: meal.date - duration) == 0 {
                    count += 1
                    sum += (interpolator.interpolateValue(at: CGFloat(meal.date.timeIntervalSince1970)) - interpolator.interpolateValue(at: CGFloat((meal.date - duration).timeIntervalSince1970))) / CGFloat(duration)
                }
            }
            let slope = count > 0 ? Double(sum) / Double(count) : 0
            var expectedBgChange = CGFloat(slope * min(Double(horizon - meal.date), 1.h))
            if bgAtMeal + expectedBgChange < 60 {
                expectedBgChange = 60 - bgAtMeal
            }
            effects.append(MealEffect(change: Double(bgAfter - bgAtMeal), carbs: carbs, units: units, slope: slope, length: horizon - meal.date))
            if effects.count > 64 {
                break
            }
        }
        return effects
    }
    static var isEstimating = false

    static func estimate3() {
        guard !isEstimating else {
            return
        }
//        defaults[.parameterCalcDate] = nil
        if let lastTime = defaults[.parameterCalcDate], lastTime > Date() - 1.d {
            return
        }
        isEstimating = true
        defer {
            isEstimating = false
        }
        let effects = getEffects()
        guard effects.count > 9 else {
            return
        }

        var s = [(ri:Double, rc: Double, ci: Double, cost:Double)]()
        for _ in 0 ..< 51 {
            let found = estimate2(effects: effects)
            if found.ri < 5 || found.rc > 80 {
                continue
            }
            log("found: ri=\(found.ri % ".1lf") rc=\(found.rc % ".1lf") ci=\(found.ci % ".1lf") cost=\(Int(found.cost))")
            s.append(found)
        }
        let f = s.sorted(by: { $0.cost < $1.cost })[0]

        defaults[.insulinRate] = s.map { $0.ri }
        defaults[.carbRate] = s.map { $0.rc }
        defaults[.carbThreshold] = s.map { $0.ci }
        defaults[.parameterCalcDate] = Date()

        log("ri=\(f.ri % ".1lf") rc=\(f.rc % ".1lf") ci=\(f.ci % ".1lf")")
    }

    static func estimate2(effects: [MealEffect]) -> (ri: Double, rc: Double, ci: Double, cost: Double) {

        var ratei = Double.random(in: 10 ... 60)
        var ratec = Double.random(in: 5 ... 20)
        var ci = Double.random(in: 0 ..< 20)
        var previous = (ratei, ratec, ci, -1.0)

        var eta = 1e-4
        let stop = 0.001
        var iter = 0
        var lastCost:Double = -1

        while iter < 9000 {
            iter += 1

            let points = effects.map { effect -> (cost: Double, dri: Double, drc: Double, dci: Double) in
                let f:Double = max(0,effect.carbs - ci) * ratec - effect.units * ratei - effect.change
                let cost:Double = f * f
                let drc:Double = 2.0 * f * max(0.0,effect.carbs - ci)
                let dri:Double = -2.0 * f * effect.units
                let dci:Double = 2.0 * f * (effect.carbs - ci > 0 ? -ratec : 0)
                return (cost: cost, dri: dri, drc: drc, dci: dci)
                }

            let costs = points.map { $0.cost }.sorted()
            let q1 = costs.percentile(0.25)
            let q3 = costs.percentile(0.75)
            let fence = 2.2 * (q3 - q1)
            let inliers = points.filter { $0.cost > q1 - fence && $0.cost < q3 + fence }
            let sums = inliers.reduce((0.0,0.0,0.0,0.0)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2, $0.3 + $1.3) }
            let cost = sums.0 / Double(inliers.count)
            let dri = sums.1 / Double(inliers.count)
            let drc = sums.2 / Double(inliers.count)
            let dci = sums.3 / Double(inliers.count)


            if cost > lastCost && lastCost > 0 {
                eta /= 10
                ratei = previous.0
                ratec = previous.1
                ci = previous.2
                lastCost = previous.3
                continue
            }
            let delta = (c: drc * eta, i: dri * eta, ci: dci * eta)
            if abs(cost - lastCost) / cost < stop {
                break
            }
            previous = (ratei,ratec,ci, lastCost)
            lastCost = cost
            ratec = max(ratec - delta.c, ratec / 2)
            ratei = max(ratei - delta.i, ratei / 2)
            ci = max(ci - delta.c, ci / 2)
        }
        return (ratei,ratec,ci, lastCost)
    }


    class Solution {
        let ratei: Double
        let ratec: Double
        let ci: Double
        var cost: Double?

        init(ratei: Double, ratec: Double, ci: Double, cost: Double? = nil) {
            self.ratei = ratei
            self.ratec = ratec
            self.ci = ci
            self.cost = cost
        }
    }

    static func geneticOptim() {
        var pop = initialPopulation()
        let effects = getEffects()
        var lastMin = Double.greatestFiniteMagnitude
        for _ in 0 ..< 50 {
            let range = evaluate(population: pop, effects: effects)
//            log("-- Generation \(iteration): min cost: \(Int(range.min))")

//            if abs(range.min - lastMin) / range.min < 0.01 {
//                lastMin = range.min
//                break
//            }
            lastMin = range.min
            pop = selection(population: pop, range: range)
            pop = mate(population: pop)
        }
        let ms = pop.first(where: { $0.cost == lastMin })!
        log("ri = \(ms.ratei), rc = \(ms.ratec), k = \(ms.ci),  cost=\(Int(lastMin))")
    }

    static private var npop = 100

    static func initialPopulation() -> [Solution] {
        var population = [Solution]()
        for _ in 0 ..< npop {
            population.append(Solution(ratei: Double.random(in: 1 ..< 60), ratec: Double.random(in: 0 ..< 40), ci: Double.random(in: 0 ..< 10), cost: nil))
        }
        return population
    }

    private static func evaluate(population: [Solution], effects: [MealEffect]) -> (min: Double, max: Double) {
        var low = Double.greatestFiniteMagnitude
        var high = Double.zero
        for i in 0 ..< population.count {
             if population[i].cost == nil {
                var costList = [Double]()
                effects.forEach {
                    let f = max(0,$0.carbs - population[i].ci) * population[i].ratec - $0.units * population[i].ratei - $0.change
                    costList.append(f*f)
                }
                let costs = costList.sorted()
                let q1 = costs.percentile(0.25)
                let q3 = costs.percentile(0.75)
                let fence = 2.2 * (q3 - q1)
                let inliers = costList.filter { $0 > q1 - fence && $0 < q3 + fence }
                let cost = inliers.sum() / Double(inliers.count)
                population[i].cost = cost
            }
            if let cost = population[i].cost {
                if cost < low {
                    low = cost
                } else if cost > high {
                    high = cost
                }
            }
        }
        return (min: low, max: high)
    }

    static func selection(population: [Solution], range: (min: Double, max: Double)) -> [Solution] {
        var out = population
        var totalCost = out.compactMap { $0.cost }.sum() - range.min * Double(population.count)
        while out.count > npop / 2 {
            var rollOfTheDice = Double.random(in: 0 ..< totalCost)
            for (idx,poorBastard) in out.enumerated() {
                guard let cost = poorBastard.cost else {
                    continue
                }
                if rollOfTheDice < cost - range.min {
                    totalCost -= cost - range.min
                    out.remove(at: idx)
                    break
                }
                rollOfTheDice -= cost - range.min
            }
        }
        return out
    }

    static func mate(population: [Solution]) -> [Solution] {
        var out = population
        while out.count < npop {
            var idx1 = 0
            var idx2 = 0
            while idx1 == idx2 {
                idx1 = Int.random(in: 0 ..< population.count)
                idx2 = Int.random(in: 0 ..< population.count)
            }
            let father = population[idx1]
            let mother = population[idx2]
            let crossover0 = Double.random(in: 0.0 ... 1.0)
            let crossover1 = Double.random(in: 0.0 ... 1.0)
            let crossover2 = Double.random(in: 0.0 ... 1.0)
            out.append(Solution(ratei: father.ratei * crossover0 + mother.ratei * (1 - crossover0),
                                ratec: father.ratec * crossover1 + mother.ratec * (1 - crossover1),
                                ci: father.ci * crossover2 + mother.ci * (1 - crossover2)))
            if Double.random(in: 0 ..< 1) < 0.01 {
                let member = out.removeLast()
                switch Int.random(in: 0 ..< 3) {
                case 0:
                    out.append(Solution(ratei: Double.random(in: 0 ..< 60), ratec: member.ratec, ci: member.ci,  cost: nil))

                case 1:
                    out.append(Solution(ratei: member.ratei, ratec: Double.random(in: 0 ..< 40), ci: member.ci,  cost: nil))

                default:
                    out.append(Solution(ratei: member.ratei, ratec: member.ratec, ci: Double.random(in: 0 ..< 10),  cost: nil))
                }
            }
        }
        return out
    }
}
