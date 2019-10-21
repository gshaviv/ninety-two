//
//  DrawingView.swift
//  WoofWoof
//
//  Created by Guy on 28/12/2018.
//  Copyright © 2018 TivStudio. All rights reserved.
//

import UIKit


class DrawingView: UIView {
    let render: (CGRect) -> Void

    init(render: @escaping (CGRect) -> Void) {
        self.render = render
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        render(rect)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
}

