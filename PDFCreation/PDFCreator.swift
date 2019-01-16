//
//  PDFCreator.swift
//  PDFCreation
//
//  Created by Guy on 12/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import PDFKit

public protocol PDFCreatorSection {
    var keepWithNext: Bool { get }
    func draw(rect: CGRect)
    func height(for width: CGFloat) -> CGFloat
}

public protocol PDFCreatorHeader: PDFCreatorSection {
    var pageNumber: Int { get set }
}

extension PDFCreatorSection {
    public var keepWithNext: Bool {
        return false
    }
}

public struct PageSize {
    public static let a4 = CGSize(width: 595, height: 842)
    public static let a3 = CGSize(width: 842, height: 1191)
    public static let a5 = CGSize(width: 420, height: 595)
    public static let letter = CGSize(width: 612, height: 792)
    public static let legal = CGSize(width: 612, height: 1008)

    public struct Landscape {
        public static let a4 = CGSize(width: 842, height: 595)
        public static let a3 = CGSize(width: 1191, height: 842)
        public static let a5 = CGSize(width: 595, height: 420)
        public static let letter = CGSize(width: 792, height: 612)
        public static let legal = CGSize(width: 1008, height: 612)
    }
}

open class PDFCreator {
    private var pageSize: CGSize

    public init(size: CGSize) {
        pageSize = CGSize(width: size.width - pageMargins.left - pageMargins.right, height: size.height - pageMargins.top - pageMargins.bottom)
    }

    private var context: UIGraphicsPDFRendererContext?
    private var yPos: CGFloat = 0
    private var pageNumber = 1
    private var pendingSections: [PDFCreatorSection] = []
    private var pendingSectionsHeight: CGFloat = 0
    public var attributes: [PDFDocumentAttribute: Any]?
    public var header: PDFCreatorHeader? {
        didSet {
            if let header = header {
                headerHeight = header.height(for: pageSize.width)
            } else {
                headerHeight = 0
            }
        }
    }
    private var headerHeight: CGFloat = 0
    public var footer: PDFCreatorHeader? = CenteredPageNumberFooter(height: 40) {
        didSet {
            if let footer = footer {
                footerHeight = footer.height(for: pageSize.width)
            } else {
                footerHeight = 0
            }
        }
    }
    private var footerHeight: CGFloat = 40
    var pageMargins = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36) {
        didSet {
            pageSize = CGSize(width: pageSize.width - pageMargins.left - pageMargins.right + oldValue.left + oldValue.right, height: pageSize.height - pageMargins.top - pageMargins.bottom + oldValue.top + oldValue.bottom)
        }
    }

    public func create(to url: URL, _ creation: (PDFCreator) -> Void) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        try renderer.writePDF(to: url) { (context) in
            drawPdf(context, creation: creation)
        }
    }

    private func drawPdf(_ context: (UIGraphicsPDFRendererContext), creation: (PDFCreator) -> Void) {
        self.context = context
        context.beginPage()
        creation(self)
        drawPending()
        drawFooter()
    }

    public func create(_ creation: (PDFCreator) -> Void) -> Data {
        let renderer: UIGraphicsPDFRenderer
        if let a = attributes {
            var attr: [String: Any] = [:]
            for (key, value) in a {
                attr[key.rawValue] = value
            }
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = attr
            renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        } else {
            renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        }
        return renderer.pdfData { (context) in
            drawPdf(context, creation: creation)
        }
    }

    public func beginPage() {
        drawFooter()
        context?.beginPage()
        yPos = 0
        pageNumber += 1
        header?.pageNumber = pageNumber
        header?.draw(rect: CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: headerHeight)))
        yPos += headerHeight
    }

    private func drawFooter() {
        let y = pageSize.height - footerHeight
        footer?.pageNumber = pageNumber
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.saveGState()
        ctx?.translateBy(x: 0, y: y)
        footer?.draw(rect: CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: footerHeight)))
        ctx?.restoreGState()
    }

    public func add(_ section: PDFCreatorSection) {
        pendingSections.append(section)
        if !section.keepWithNext {
            drawPending()
        } else {
            pendingSectionsHeight += section.height(for: pageSize.width)
            if yPos + pendingSectionsHeight > pageSize.height - footerHeight {
                beginPage()
            }
        }
    }

    private func drawPending() {
        let ctx = UIGraphicsGetCurrentContext()
        let totalH = pendingSections.reduce(0) { $0 + $1.height(for: pageSize.width) }
        if yPos + totalH > pageSize.height - footerHeight {
            beginPage()
        }
        for section in pendingSections {
            let h = section.height(for: pageSize.width)
            ctx?.saveGState()
            ctx?.translateBy(x: 0, y: yPos)
            section.draw(rect: CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: h)))
            ctx?.restoreGState()
            yPos += h
        }
        pendingSections = []
        pendingSectionsHeight = 0
    }
}


extension String {
     subscript(index: Int) -> String {
        get {
            return String(self[self.index(self.startIndex, offsetBy: index)])
        }
        set {
            self[index ..< index + 1] = newValue
        }
    }

     subscript(integerRange: Range<Int>) -> String {
        get {
            let start = index(startIndex, offsetBy: integerRange.lowerBound)
            let end = index(startIndex, offsetBy: integerRange.upperBound)
            return String(self[start ..< end])
        }
        set {
            let start = index(startIndex, offsetBy: integerRange.lowerBound)
            let end = index(startIndex, offsetBy: integerRange.upperBound)
            replaceSubrange(start ..< end, with: newValue)
        }
    }

     subscript(from: CountablePartialRangeFrom<Int>) -> String {
        get {
            let start = index(startIndex, offsetBy: from.lowerBound)
            return String(self[start ..< endIndex])
        }
        set {
            let start = index(startIndex, offsetBy: from.lowerBound)
            replaceSubrange(start ..< endIndex, with: newValue)
        }
    }

     subscript(upTo: PartialRangeUpTo<Int>) -> String {
        get {
            guard let upper = index(startIndex, offsetBy: upTo.upperBound, limitedBy: endIndex) else {
                return ""
            }
            return String(self[startIndex ..< upper])
        }
        set {
            guard let upper = index(startIndex, offsetBy: upTo.upperBound, limitedBy: endIndex) else {
                return
            }
            replaceSubrange(startIndex ..< upper, with: newValue)
        }
    }
}

extension Array where Element: Numeric, Element: Comparable {
    func sum() -> Element {
        return reduce(0, +)
    }

    func biggest() -> Element {
        return reduce(self[0]) { Swift.max($0, $1) }
    }

    func smallest() -> Element {
        return reduce(self[0]) { Swift.min($0, $1) }
    }
}
