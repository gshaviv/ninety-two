//
//  FoodViewController.swift
//  WoofWoof
//
//  Created by Guy on 23/03/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit

class FoodViewController: UIViewController {
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var manufacturerLabel: UILabel!
    @IBOutlet var servingLabel: UILabel!
    @IBOutlet var carbsLabel: UILabel!
    @IBOutlet var ingredientsView: UITextView!
    @IBOutlet var mainStack: UIStackView!
    var food: Food!
    weak var origin: PrepareMealViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        nameLabel.text = food.name.capitalized
        manufacturerLabel.text = food.manufacturer?.capitalized
        ingredientsView.text = food.ingredients?.listCase().replacingOccurrences(of: ".", with: "\n")
        servingLabel.text = "\(food.householdSize.asFraction()) \(food.householdName)"
        carbsLabel.text = "\((food.carbs*food.serving/100).formatted(with: "%.0lf"))g per serving"

        preferredContentSize = mainStack.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width - 40, height: 0), withHorizontalFittingPriority: UILayoutPriority.required, verticalFittingPriority: UILayoutPriority.fittingSizeLevel)

        let iv = UILabel(frame: .zero)
        iv.numberOfLines = 0
        iv.text = ingredientsView.text
        iv.font = ingredientsView.font
        let size = iv.sizeThatFits(CGSize(width: UIScreen.main.bounds.width - 40, height: UIScreen.main.bounds.height - 200))

        preferredContentSize.height += size.height + 32
    }

    override var previewActionItems: [UIPreviewActionItem] {
        return [UIPreviewAction(title: "Add 1 Serving", style: .default, handler: { (_, ctr) in
            guard let ctr = ctr as? FoodViewController, let parent = ctr.origin else {
                return
            }
            parent.didSelectAmount(ctr.food.householdSize, from: ctr.food)
        })]
    }
}
