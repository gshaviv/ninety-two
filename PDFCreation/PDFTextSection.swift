//
//  PDFTextSection.swift
//  PDFCreation
//
//  Created by Guy on 12/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import UIKit

open class PDFTextSection {
    let attributedString: NSAttributedString
    private(set) public var keepWithNext: Bool
    public var margin: UIEdgeInsets

    public init(_ atr: NSAttributedString, margin: UIEdgeInsets = .zero, keepWithNext: Bool = false) {
        attributedString = atr
        self.keepWithNext = keepWithNext
        self.margin = margin
    }
}

extension PDFTextSection: PDFCreatorSection {

    public func height(for width: CGFloat) -> CGFloat {
        return attributedString.boundingRect(with: CGSize(width: width - margin.left - margin.right, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil).height + margin.top + margin.bottom
    }

    public func draw(rect: CGRect) {
        let container = rect.inset(by: margin)
        attributedString.draw(in: container)
    }
}

open class PDFTextCell: PDFTextSection, PDFCreatorCell {
    public var width: CGFloat {
        return attributedString.size().width
    }
}
