//
//  AkimaInterpolator.swift
//  GraphBuilder
//
//  Created by Виталий Антипов on 07.01.17.
//  Copyright © 2017 Виталий Антипов. All rights reserved.
//

import UIKit
public class AkimaInterpolator {
  private let points: [CGPoint]
  private var m: [CGFloat]
  private var n: Int
  private var t: [CGFloat]
  private var a: [CGFloat]
  private var b: [CGFloat]
  private var c: [CGFloat]
  private var d: [CGFloat]
  
  public init(points input: [CGPoint]) {
    var points = [input[0]]
    for point in input[1...] {
        if let last = points.last, point.x > last.x {
            points.append(point)
        }
    }
    self.points = points
    n = points.count
    m = Array<CGFloat>(repeatElement(0.0, count: n + 3))
    t = Array<CGFloat>(repeatElement(0.0, count: n))
    a = Array<CGFloat>(repeatElement(0.0, count: n))
    b = Array<CGFloat>(repeatElement(0.0, count: n))
    c = Array<CGFloat>(repeatElement(0.0, count: n))
    d = Array<CGFloat>(repeatElement(0.0, count: n))
    calcM()
    calcT()
    calcKoefs()
  }
  
  private func calcM() {
    for i in 2..<n + 1 {
      m[i] = (points[i - 1].y - points[i - 2].y) / (points[i - 1].x - points[i - 2].x)
    }
    m[0] = 3 * m[2] - 2 * m[3]
    m[1] = 2 * m[2] - 2 * m[3]
    m[n + 1] = 2 * m[n] - 2 * m[n-1]
    m[n + 2] = 3 * m[n] - 2 * m[n-1]
  }
  
  private func calcT() {
    for i in 0..<n-1 {
      let den = abs(m[i + 3] - m[i + 2]) + abs(m[i + 1] - m[i])
      if den > 0 {
        let num=abs(m[i+3] - m[i+2])*m[i+1] + abs(m[i+1] - m[i])*m[i+2];
        t[i] = num / den
        
      } else {
        t[i] = m[i + 1]
        t[i] = m[i + 2]
      }
    }
  }
  
  private func calcKoefs() {
    for i in 0..<n-1 {
      a[i] = points[i].y
      b[i] = t[i]
      let h = points[i + 1].x - points[i].x
      c[i] = (3 * m[i+2] - 2 * t[i] - t[i+1]) / h
      d[i] = (t[i] + t[i+1] - 2 * m[i+2]) / (h * h)
    }
  }
  
  public func interpolateValue(at x: CGFloat) -> CGFloat {
    let index = points.lastIndex(where: { x > $0.x }) ?? 0
    let dx = x - points[index].x
    return a[index] + b[index] * dx + c[index] * dx * dx + d[index] * dx * dx * dx
  }

    public var maxX: CGFloat {
        return points.last?.x ?? 0
    }
  
}
