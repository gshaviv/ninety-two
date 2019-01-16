//
//  PDFSections.swift
//  PDFCreation
//
//  Created by Guy on 13/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation


public class PDFFixedHeightBlockSection: PDFCreatorSection {
    var drawing: ((CGRect) -> Void)?
    let height: CGFloat

    public init(h:CGFloat, drawingBlock: @escaping (CGRect) -> Void) {
        self.height = h
        drawing = drawingBlock
    }

    public func draw(rect: CGRect) {
        drawing?(rect)
        drawing = nil
    }

    public func height(for width: CGFloat) -> CGFloat {
        return height
    }
}

public class PDFVariableHeightBlockSection: PDFCreatorSection {
    var drawing: ((CGRect) -> Void)?
    var heightBlock: ((CGFloat)->CGFloat)?

    public init(h:@escaping (CGFloat)->CGFloat, drawingBlock: @escaping (CGRect) -> Void) {
        self.heightBlock = h
        drawing = drawingBlock
    }

    public func draw(rect: CGRect) {
        drawing?(rect)
        drawing = nil
        heightBlock = nil
    }

    public func height(for width: CGFloat) -> CGFloat {
        return heightBlock?(width) ?? 0
    }
}

public struct PDFSpace: PDFCreatorSection {
    let h: CGFloat

    public init(_ h: CGFloat) {
        self.h = h
    }
    public func draw(rect: CGRect) {

    }

    public func height(for width: CGFloat) -> CGFloat {
        return h
    }


}
