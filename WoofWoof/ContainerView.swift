//
//  EmbedingView.swift
//  WoofWoof
//
//  Created by Guy on 25/02/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import WoofKit

class ContainerView: UIView {
    public var containedController: UIViewController? {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        return containedController?.preferredContentSize ?? .zero
    }

    override func addSubview(_ view: UIView) {
        super.addSubview(view)
        if containedController == nil {
            if let v = view.controller as? UINavigationController {
                containedController = v.viewControllers.first
            } else {
                containedController = view.controller
            }
        }
    }
}
