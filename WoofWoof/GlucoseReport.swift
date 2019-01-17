//
//  GlucoseReport.swift
//  WoofWoof
//
//  Created by Guy on 13/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import PDFKit
import PDFCreation
import Sqlable
import WoofKit

class GlucoseReport {
    let period: TimeInterval
    let start: Date
    let end: Date
    let db: SqliteDatabase
    var readings: [GlucosePoint]!

    enum ReportError: Error {
        case noData
        case badData
    }

    let titleFont = UIFont(name: "Helvetica-Bold", size: 24)
    let subtitleFont = UIFont(name: "Helvetica", size: 18)
    let normalFont = UIFont(name: "Helvetica", size: 12)

    init(period: TimeInterval, from db: SqliteDatabase) throws {
        self.period = period
        end = Date()
        start = end - period
        self.db = try db.createChild()
    }

    init(from: Date, to: Date, database: SqliteDatabase) throws {
        self.period = from - to
        end = to
        start = from
        self.db = try database.createChild()
    }

    func create() throws -> PDFDocument {
        readings = try db.perform(GlucosePoint.read().filter(GlucosePoint.date > start && GlucosePoint.date < end && GlucosePoint.value > 0).orderBy(GlucosePoint.date))
        if readings.isEmpty {
            throw ReportError.noData
        }

        let diffs = readings.map { $0.date.timeIntervalSince1970 }.diff()
        let withTime = zip(readings.dropLast(), diffs)
        let withGoodTime = withTime.filter { $0.1 < 20.m }
        var minValue: Double = 999
        var maxValue: Double = -1
        let (sumG, totalT, timeBelow, timeIn, timeAbove) = withGoodTime.reduce((0.0, 0.0, 0.0, 0.0, 0.0)) { (result, arg) -> (Double, Double, Double, Double, Double) in
            let (sum, total, below, inRange, above) = result
            let (gp, duration) = arg
            let x0 = sum + gp.value * duration
            let x1 = total + duration
            let x2 = gp.value < defaults[.minRange] ? below + duration : below
            let x3 = gp.value >= defaults[.minRange] && gp.value < defaults[.maxRange] ? inRange + duration : inRange
            let x4 = gp.value >= defaults[.maxRange] ? above + duration : above
            minValue = min(minValue, gp.value)
            maxValue = max(maxValue, gp.value)
            return (x0, x1, x2, x3, x4)
        }
        let aveG = sumG / totalT
        let a1c = (aveG / 18.05 + 2.52) / 1.583

        var lowEvents = [[GlucosePoint]]()
        var lastPoint:GlucosePoint? = nil
        var currentEvent = [GlucosePoint]()
        var inEvent = false
        for point in readings {
            if point.value < 70 {
                if !inEvent, let last = lastPoint {
                    currentEvent.append(last)
                }
                inEvent = true
                currentEvent.append(point)
            } else if inEvent {
                currentEvent.append(point)
                lowEvents.append(currentEvent)
                inEvent = false
                currentEvent = []
            }
            lastPoint = point
        }



        let maker = PDFCreator(size: PageSize.a4)
        let data = maker.create { sender in
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            maker.add(PDFTextSection("Report for \(dateFormatter.string(from: start)) to \(dateFormatter.string(from: end))".styled.text(alignment: .center).font(titleFont), margin: UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0), keepWithNext: true))

            let table = PDFTableSection(padding: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4))
            try? table.addRow([
                PDFTextCell("Above target".styled.font(normalFont).traits(.traitBold).text(alignment: .center)),
                PDFTextCell("In target".styled.font(normalFont).traits(.traitBold).text(alignment: .center)),
                PDFTextCell("Below target".styled.font(normalFont).traits(.traitBold).text(alignment: .center)),
            ])

            try? table.addRow([
                PDFTextCell(String(format: "%.0lf%%", timeAbove / totalT * 100).styled.font(normalFont).text(alignment: .center)),
                PDFTextCell(String(format: "%.0lf%%", timeIn / totalT * 100).styled.font(normalFont).text(alignment: .center)),
                PDFTextCell(String(format: "%.0lf%%", timeBelow / totalT * 100).styled.font(normalFont).text(alignment: .center)),
            ])

            try? table.addRow([
                PDFTextCell("Average glucose".styled.font(normalFont).traits(.traitBold).text(alignment: .center)),
                PDFTextCell("Estimated A1C".styled.font(normalFont).traits(.traitBold).text(alignment: .center)),
                PDFTextCell("# Low events".styled.font(normalFont).traits(.traitBold).text(alignment: .center)),
            ])

            try? table.addRow([
                PDFTextCell("\(Int(round(aveG))) mg/dL".styled.font(normalFont).text(alignment: .center)),
                PDFTextCell(String(format: "%.1lf%%", a1c).styled.font(normalFont).text(alignment: .center)),
                PDFTextCell("\(lowEvents.count)".styled.font(normalFont).text(alignment: .center)),
            ])
            table.rowBorderPattern = "- - -"

            maker.add(table)

            if lowEvents.count > 0 {
                maker.add(PDFSpace(20))
                maker.add(PDFTextSection("Low Glucose Events".styled.font(self.subtitleFont)))
                let lows = PDFFixedHeightBlockSection(h: 160) { rect in
                    let ctx = UIGraphicsGetCurrentContext()
                    let yMaxValue = Double(70)
                    let yMinValue = floor(minValue / 5) * 5
                    let topMargin:Double = 8
                    let yDist = Double(rect.height) - topMargin - 40
                    let yPos = { (y: Double) in CGFloat((yMaxValue - y) / (yMaxValue - yMinValue) * yDist) }
                    ctx?.translateBy(x: 0, y: CGFloat(topMargin))
                    var wMax:CGFloat = 0
                    for y in stride(from: yMaxValue, to: yMinValue, by: -10) {
                        let num = "\(Int(y))".styled.font(self.normalFont)
                        let s = num.size()
                        wMax = max(wMax, s.width)
                        let yCoor = yPos(y)
                        let area = CGRect(x: 0, y: yCoor - s.height / 2, width: s.width, height: s.height)
                        num.draw(in: area)
                    }
                    ctx?.translateBy(x: wMax + 4, y: 0)
                    let graphRect = rect.inset(by: UIEdgeInsets(top: 0.0, left: 0.0, bottom: CGFloat(topMargin) + 40, right: wMax * 2 + 4))

                    ctx?.setLineWidth(0.5)
                    UIColor.lightGray.setStroke()
                    ctx?.beginPath()
                    for y in stride(from: yMaxValue, to: yMinValue, by: -10) {
                        let yc = yPos(y)
                        ctx?.move(to: CGPoint(x: 0, y: yc))
                        ctx?.addLine(to: CGPoint(x: graphRect.maxX, y: yc))
                    }
                    ctx?.strokePath()
                    for x in 0 ... 12 {
                        let time = String(format: "%02ld:00",(x == 12 ? 0 : x) * 2).styled.font(self.normalFont)
                        let size = time.size()
                        let xCenter = CGFloat(x) * graphRect.width / 12.0
                        let area = CGRect(origin: CGPoint(x: xCenter - size.width / 2, y: graphRect.maxY + 4), size: size)
                        time.draw(in: area)
                        ctx?.setLineWidth(0.5)
                        UIColor.lightGray.setStroke()
                        ctx?.beginPath()
                        ctx?.move(to: CGPoint(x: xCenter, y: 0))
                        ctx?.addLine(to: CGPoint(x: xCenter, y: graphRect.maxY))
                        ctx?.strokePath()
                    }
                    let xPos = { (time:TimeInterval) -> CGFloat in CGFloat(time) / 86400 * graphRect.width }
                    UIColor.black.setStroke()
                    ctx?.stroke(graphRect)
                    ctx?.clip(to: graphRect)

                    UIColor.red.setStroke()
                    UIColor(red: 1, green: 0, blue: 0, alpha: 0.1).setFill()

                    for event in lowEvents {
                        guard let eventStart = event.first else {
                            continue
                        }
                        let base = eventStart.date.midnightBefore
                        let points = event.map { CGPoint(x: xPos($0.date - base), y: yPos($0.value)) }
                        let path = UIBezierPath()
                        path.move(to: points[0])
                        path.addCurveThrough(points: points[1...])
                        path.addLine(to: points[0])
                        path.fill()
                        path.stroke()
                        if points.map({ $0.x }).biggest() > graphRect.width {
                            let later = base + 24.h
                            let points = event.map { CGPoint(x: xPos($0.date - later), y: yPos($0.value)) }
                            let path = UIBezierPath()
                            path.move(to: points[0])
                            path.addCurveThrough(points: points[1...])
                            path.addLine(to: points[0])
                            path.fill()
                            path.stroke()
                        }
                    }
                }
                maker.add(lows)
            }

            self.patternReport(maker: maker)
            maker.beginPage()
            self.dailyLogs(maker: maker)
        }
        if let doc = PDFDocument(data: data) {
            return doc
        } else {
            throw ReportError.badData
        }
    }

    private func patternReport(maker: PDFCreator) {
        var buckets = Array(repeating: [Double](), count: 24)
        readings.forEach {
            let inBucket = Int(($0.date - $0.date.midnightBefore) / 3600.0)
            buckets[inBucket].append($0.value)
        }

        var p25 = [Double]()
        var p10 = [Double]()
        var p50 = [Double]()
        var p75 = [Double]()
        var p90 = [Double]()
        for range in [(buckets.count - 1) ..< buckets.count, 0 ..< buckets.count, 0 ..< 1] {
            for idx in range {
                buckets[idx] = buckets[idx].sorted()
                p50.append(buckets[idx].median())
                p10.append(buckets[idx].percentile(0.1))
                p25.append(buckets[idx].percentile(0.25))
                p75.append(buckets[idx].percentile(0.75))
                p90.append(buckets[idx].percentile(0.9))
            }
        }

        maker.add(PDFTextSection("Daily Patterns".styled.font(subtitleFont), margin: UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 0), keepWithNext: true))

        maker.add(PDFFixedHeightBlockSection(h: 216) { (rect) in
            let ctx = UIGraphicsGetCurrentContext()
            let gMin = min(floor(p10.smallest() / 10) * 10, defaults[.minRange])
            let gMax = max(ceil(p90.biggest() / 10)  * 10, defaults[.maxRange])
            let graphRect = CGRect(x: 28, y: 16, width: rect.width - 80, height: rect.height - 36)
            let yPos = { (y: Double) in CGFloat(gMax - y) / CGFloat(gMax - gMin) * graphRect.height }
            ctx?.saveGState()
            ctx?.translateBy(x: graphRect.minX, y: graphRect.minY)

            UIColor.lightGray.setStroke()
            ctx?.setLineWidth(0.5)
            for y in stride(from: floor(gMax/50)*50, to: gMin, by: -50) {
                let num = "\(Int(y))".styled.font(self.normalFont)
                let s = num.size()
                let yCoor = yPos(y)
                let area = CGRect(x: -4 - s.width, y: yCoor - s.height / 2, width: s.width, height: s.height)
                num.draw(in: area)
            }

            UIColor.darkGray.setStroke()
            ctx?.setLineWidth(1)
            for y in [defaults[.maxRange], defaults[.minRange]] {
                let num = "\(Int(y))".styled.font(self.normalFont)
                let s = num.size()
                let yCoor = yPos(y)
                let area = CGRect(x: -4 - s.width, y: yCoor - s.height / 2, width: s.width, height: s.height)
                num.draw(in: area)
                ctx?.beginPath()
                ctx?.move(to: CGPoint(x: 0, y: yCoor))
                ctx?.addLine(to: CGPoint(x: graphRect.width, y: yCoor))
                ctx?.strokePath()
            }

            let xPos = { (t: Double) in CGFloat(t) / 86400 * graphRect.width }
            for x in 0 ... 12 {
                let time = String(format: "%02ld",x * 2).styled.font(self.normalFont)
                let size = time.size()
                let xCenter = CGFloat(x) * graphRect.width / 12.0
                let area = CGRect(origin: CGPoint(x: xCenter - size.width / 2, y: graphRect.height + 4), size: size)
                time.draw(in: area)
                ctx?.setLineWidth(0.5)
                ctx?.beginPath()
                ctx?.move(to: CGPoint(x: xCenter, y: 0))
                ctx?.addLine(to: CGPoint(x: xCenter, y: graphRect.height))
                ctx?.strokePath()
            }

            ctx?.saveGState()
            ctx?.clip(to: CGRect(origin: .zero, size: graphRect.size))
            let a10 = UIBezierPath()
            let coor10 = p10.enumerated().map { CGPoint(x: xPos(Double($0.0) * 60 * 60 - 30.0 * 60), y: yPos($0.1)) }
            let coor90 = Array(p90.enumerated().map { CGPoint(x: xPos(Double($0.0) * 60 * 60 - 30.0 * 60), y: yPos($0.1)) }.reversed())
            a10.move(to: coor10[0])
            a10.addCurveThrough(points: coor10[1...])
            a10.addLine(to: coor90[0])
            a10.addCurveThrough(points: coor90[1...])
            a10.addLine(to: coor10[0])

            let coor25 = p25.enumerated().map { CGPoint(x: xPos(Double($0.0) * 60 * 60 - 30.0 * 60), y: yPos($0.1)) }
            let coor75 = Array(p75.enumerated().map { CGPoint(x: xPos(Double($0.0) * 60 * 60 - 30.0 * 60), y: yPos($0.1)) }.reversed())
            let a25 = UIBezierPath()
            a25.move(to: coor25[0])
            a25.addCurveThrough(points: coor25[1...])
            a25.addLine(to: coor75[0])
            a25.addCurveThrough(points: coor75[1...])
            a25.addLine(to: coor25[0])

            let coor50 = p50.enumerated().map { CGPoint(x: xPos(Double($0.0) * 60 * 60 - 30.0 * 60), y: yPos($0.1)) }
            let median = UIBezierPath()
            median.move(to: coor50[0])
            median.addCurveThrough(points: coor50[1...])

            UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.5).setFill()
            a10.fill()
            UIColor(red: 0.2, green: 0.2, blue: 0.4, alpha: 0.5).set()
            a25.fill()
            ctx?.setLineWidth(2)
            UIColor.black.set()
            median.stroke()
            ctx?.restoreGState()

            var top: CGFloat = 0
            do {
                let text = "Median".styled.font(self.normalFont)
                let size = text.size()
                let area = CGRect(origin: CGPoint(x: graphRect.width + 4, y: (coor50.last!.y + coor50[coor50.count - 2].y - size.height) / 2), size: size)
                text.draw(in: area)
                top = area.minY
            }
            do {
                let text = "25%".styled.font(self.normalFont)
                let size = text.size()
                var area = CGRect(origin: CGPoint(x: graphRect.width + 4, y: (coor50.last!.y + coor75.last!.y - size.height) / 2), size: size)
                if area.maxY > top {
                    area.origin.y = top - area.height
                }
                text.draw(in: area)
                top = area.minY
            }
            do {
                let text = "10%".styled.font(self.normalFont)
                let size = text.size()
                var area = CGRect(origin: CGPoint(x: graphRect.width + 4, y: (coor90.last!.y + coor75.last!.y - size.height) / 2), size: size)
                if area.maxY > top {
                    area.origin.y = top - area.height
                }
                text.draw(in: area)
            }
            ctx?.restoreGState()
            UIColor.black.set()
            ctx?.stroke(graphRect)
        })
    }

    private func dailyLogs(maker: PDFCreator) {
        maker.add(PDFTextSection("Daily Logs".styled.font(subtitleFont), margin: UIEdgeInsets(top: 4, left: 0, bottom: 2, right: 0), keepWithNext: true))

        let start = self.start.midnightBefore + 12.h
        var day = start
        if day - 12.h < self.start {
            day += 1.d
        }

        let v = self.readings.map { $0.value }
        let gmin = min(floor(v.smallest() / 5) * 5, defaults[.minRange])
        let gmax = max(ceil(v.biggest()/10)*10, defaults[.maxRange])
        while day + 12.h < end {
            dayLog(for: day, min: gmin, max: gmax, maker: maker)
            day += 1.d
        }
    }

    private func dayLog(for day: Date, min gmin:Double, max gmax:Double, maker: PDFCreator) {
        guard let ctx = UIGraphicsGetCurrentContext() else {
            return
        }
        let dayStart = day - 12.h
        let dayEnd = day + 12.h
        let points = self.readings.filter({ $0.date > dayStart && $0.date < dayEnd })
        if points.count < 24 {
            return
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        maker.add(PDFTextSection(formatter.string(from: day).styled.font(normalFont), margin: UIEdgeInsets(top: 6, left: 0, bottom: 4, right: 0), keepWithNext: true))
        maker.add(PDFFixedHeightBlockSection(h:120) { (rect) in
            let graphRect = CGRect(x: 28, y: 0, width: rect.width - 58, height: rect.height - 36)
            let yPos = { (y: Double) in CGFloat(gmax - y) / CGFloat(gmax - gmin) * graphRect.height + graphRect.minY}
            let xPos = { (x: Date) in CGFloat(x - dayStart) / 86400.0 * graphRect.width + graphRect.minX }
            UIColor(white: 0.2, alpha: 1).setStroke()
            ctx.setLineWidth(0.5)
            for y in stride(from: floor(gmax/50)*50, to: gmin, by: -50) {
                let num = "\(Int(y))".styled.font(self.normalFont).sizeFactor(0.75)
                let s = num.size()
                let yCoor = yPos(y)
                let area = CGRect(x: graphRect.minX - 4 - s.width, y: yCoor - s.height / 2, width: s.width, height: s.height)
                num.draw(in: area)
            }

            UIColor.darkGray.setStroke()
            ctx.setLineWidth(1)
            for y in [defaults[.maxRange], defaults[.minRange]] {
                let num = "\(Int(y))".styled.font(self.normalFont).sizeFactor(0.75)
                let s = num.size()
                let yCoor = yPos(y)
                let area = CGRect(x: graphRect.maxX + 2, y: yCoor - s.height / 2, width: s.width, height: s.height)
                num.draw(in: area)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: graphRect.minX, y: yCoor))
                ctx.addLine(to: CGPoint(x: graphRect.maxX, y: yCoor))
                ctx.strokePath()
            }

            var x = dayStart
            UIColor(white: 0.2, alpha: 1).setStroke()
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            repeat {
                let time = String(format: "%02ld",x.hour).styled.font(self.normalFont)
                let size = time.size()
                let xCenter = xPos(x)
                let area = CGRect(origin: CGPoint(x: xCenter - size.width / 2, y: graphRect.height + 4), size: size)
                time.draw(in: area)
                ctx.setLineWidth(0.5)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: xCenter, y: graphRect.minY))
                ctx.addLine(to: CGPoint(x: xCenter, y: graphRect.maxY))
                ctx.strokePath()

                x += 2.h
            } while x < dayEnd

            ctx.saveGState()
            ctx.clip(to: graphRect)
            let path = UIBezierPath()
            let gPoints = points.map { CGPoint(x: xPos($0.date), y: yPos($0.value)) }
            path.move(to: gPoints[0])
            path.addCurveThrough(points: gPoints[1...])
            let minPoint = points.reduce(points[0]) { $0.value < $1.value ? $0 : $1 }
            let maxPoint = points.reduce(points[0]) { $0.value > $1.value ? $0 : $1 }
            do {
                let text = "\(Int(round(maxPoint.value)))".styled.font(self.normalFont).sizeFactor(0.75).traits(.traitBold)
                let size = text.size()
                var area = CGRect(x: xPos(maxPoint.date) - size.width / 2, y: yPos(maxPoint.value) - size.height - 2, width: size.width, height: size.height)
                if area.maxY > graphRect.maxY {
                    area = CGRect(x: xPos(maxPoint.date) - size.width / 2, y: yPos(maxPoint.value) + 4, width: size.width, height: size.height)
                } else if area.minY < graphRect.minY {
                    area.origin.y += graphRect.minY - area.minY
                }
                if area.maxX > graphRect.maxX {
                    area.origin.x -= area.maxX - graphRect.maxX
                } else if area.minX < graphRect.minX {
                    area.origin.x += graphRect.minX - area.minX
                }
                text.draw(in: area)
            }
            do {
                let text = "\(Int(round(minPoint.value)))".styled.font(self.normalFont).sizeFactor(0.75).traits(.traitBold)
                let size = text.size()
                var area = CGRect(x: xPos(minPoint.date) - size.width / 2, y: yPos(minPoint.value) + 2, width: size.width, height: size.height)
                if area.maxY > graphRect.maxY {
                    area.origin.y = graphRect.maxY -  area.height - 2
                } else if area.minY < graphRect.minY {
                    area = CGRect(x: xPos(minPoint.date) - size.width / 2, y: yPos(minPoint.value) - size.height - 4, width: size.width, height: size.height)
                }
                if area.maxX > graphRect.maxX {
                    area.origin.x =  graphRect.maxX - area.width - 2
                } else if area.minX < graphRect.minX {
                    area.origin.x = graphRect.minX + 2
                }
                text.draw(in: area)
            }

            ctx.restoreGState()

            UIColor.black.setStroke()
            ctx.setLineWidth(1)
            path.stroke()

            ctx.stroke(graphRect)

        })
    }
}