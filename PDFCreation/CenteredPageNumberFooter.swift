//
//  CenteredPageNumberFooter.swift
//  PDFCreation
//
//  Created by Guy on 12/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation

struct CenteredPageNumberFooter: PDFCreatorHeader {
    var pageNumber: Int = 0

    func draw(rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()
        if drawSeperator {
            ctx?.move(to: CGPoint(x: 0, y: 10))
            ctx?.addLine(to: CGPoint(x: rect.width, y: 10))
            ctx?.setLineWidth(2)
            UIColor.black.set()
            ctx?.strokePath()
        }
        let num = "- \(pageNumber) -"
        let a = NSAttributedString(string: num, attributes: [NSAttributedString.Key.font: UIFont(name: "Helvetica", size: 11)!])
        let size = a.size()
        a.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY + 5 - size.height / 2))
    }

    func height(for width: CGFloat) -> CGFloat {
        return footerHeight
    }

    let footerHeight: CGFloat
    let drawSeperator: Bool

    init(height: CGFloat, seperator: Bool = true) {
        footerHeight = height
        drawSeperator = seperator
    }
}
