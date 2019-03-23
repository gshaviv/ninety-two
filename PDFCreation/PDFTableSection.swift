//
//  PDFTableSection.swift
//  PDFCreation
//
//  Created by Guy on 13/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation

public protocol PDFCreatorCell: PDFCreatorSection {
    var width: CGFloat { get }
}

open class PDFTableSection {
    private var rows = [[PDFCreatorCell]]()
    private var rowHeight = [CGFloat]()
    private var columnWidth = [CGFloat]()
    public var padding: UIEdgeInsets
    public var borderWidth:CGFloat = 1
    public var borderColor = UIColor.black
    public var columnBorderPattern: String
    public var rowBorderPattern: String

    public init(padding: UIEdgeInsets = .zero, columBorderPattern: String = "|", rowBorderPattern: String = "-") {
        self.columnBorderPattern = columBorderPattern
        self.rowBorderPattern = rowBorderPattern
        self.padding = padding
    }
    
    public enum TableError: Error {
        case wrongNumberOfCells
    }

    public func addRow(_ row: [PDFCreatorCell]) throws {
        if !rows.isEmpty {
            guard rows[0].count == row.count else {
                throw TableError.wrongNumberOfCells
            }
        }
        rows.append(row)
    }
}

extension PDFTableSection: PDFCreatorSection {
    public func draw(rect: CGRect) {
        drawGrid(rect: rect)
        drawCells()
    }

    private func drawGrid(rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()
        let totalWidth = columnWidth.sum() + CGFloat(columnWidth.count) * (padding.left + padding.right)
        let totalHeight = rowHeight.sum() + CGFloat(rowHeight.count) * (padding.top + padding.bottom)
        if rect.width > totalWidth {
            ctx?.translateBy(x: (rect.width - totalWidth) / 2, y: 0)
        }
        var y:CGFloat = 0
        ctx?.saveGState()
        borderColor.setStroke()
        ctx?.setLineWidth(borderWidth)
        for (idx,h) in rowHeight.enumerated() {
            if rowBorderPattern[idx % rowBorderPattern.count] != " " {
                ctx?.move(to: CGPoint(x: 0, y: y))
                ctx?.addLine(to: CGPoint(x: totalWidth, y: y))
            }
            y += h + padding.top + padding.bottom
        }
        if rowBorderPattern[rowHeight.count % rowBorderPattern.count] != " " {
            ctx?.move(to: CGPoint(x: 0, y: y))
            ctx?.addLine(to: CGPoint(x: totalWidth, y: y))
        }
        var x: CGFloat = 0
        for (idx,w) in columnWidth.enumerated() {
            if columnBorderPattern[idx % columnBorderPattern.count] != " " {
                ctx?.move(to: CGPoint(x: x, y: 0))
                ctx?.addLine(to: CGPoint(x: x, y: totalHeight))
            }
            x += w + padding.left + padding.right
        }
        if columnBorderPattern[columnWidth.count % columnBorderPattern.count] != " " {
            ctx?.move(to: CGPoint(x: x, y: 0))
            ctx?.addLine(to: CGPoint(x: x, y: totalHeight))
        }
        ctx?.strokePath()
        ctx?.restoreGState()
    }

    private func drawCells() {
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.saveGState()
        ctx?.translateBy(x: 0, y: padding.top)
        for i in 0 ..< rowHeight.count {
            ctx?.saveGState()
            ctx?.translateBy(x: padding.left, y: 0)
            for j in 0 ..< columnWidth.count {
                let cell = rows[i][j]
                cell.draw(rect: CGRect(origin: .zero, size: CGSize(width: columnWidth[j], height: rowHeight[i])))
                ctx?.translateBy(x: columnWidth[j] + padding.left + padding.right, y: 0)
            }
            ctx?.restoreGState()
            ctx?.translateBy(x: 0, y: rowHeight[i] + padding.bottom + padding.top)
        }
        ctx?.restoreGState()
    }


    public func height(for width: CGFloat) -> CGFloat {
        if columnWidth.isEmpty {
            var sum:CGFloat = 0
            for col in 0 ..< rows[0].count {
                let wid = rows.reduce(0) { max($0, $1[col].width) }
                columnWidth.append(wid)
                sum += wid
            }
            sum += padding.left

            let factor = max(min(0.85, width / (sum + (padding.left + padding.right) * CGFloat(columnWidth.count))), 1.25)
            for i in 0 ..< columnWidth.count {
                columnWidth[i] *= factor
            }

            for row in rows {
                var h = CGFloat(0)
                for (idx,cell) in row.enumerated() {
                    h = max(h, cell.height(for: columnWidth[idx]))
                }
                rowHeight.append(h)
            }
        }

        return rowHeight.sum() + CGFloat(rowHeight.count) * (padding.top + padding.bottom)
    }
}

extension Array where Element: Numeric, Element: Comparable {
    fileprivate func sum() -> Element {
        return reduce(0, +)
    }

    fileprivate func biggest() -> Element {
        return reduce(self[0]) { Swift.max($0, $1) }
    }

    fileprivate func smallest() -> Element {
        return reduce(self[0]) { Swift.min($0, $1) }
    }
}
