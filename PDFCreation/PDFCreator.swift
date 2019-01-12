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

open class PDFCreator {
    public struct Size {
        static public let a4 = CGSize(width: 595, height: 842)
    }
    let pageSize: CGSize

    public init(size: CGSize) {
        pageSize = size
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

    public func create( _ creation: (PDFCreator) -> Void) -> Data {
        let renderer:UIGraphicsPDFRenderer
        if let a = attributes  {
            var attr: [String:Any] = [:]
            for (key,value) in a {
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
        for section in pendingSections {
            let h = section.height(for: pageSize.width)
            if yPos + h > pageSize.height - footerHeight {
                beginPage()
            }
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
