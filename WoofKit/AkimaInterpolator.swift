//
//  AkimaInterpolator.swift
//  GraphBuilder
//
//  Created by Виталий Антипов on 07.01.17.
//  Copyright © 2017 Виталий Антипов. All rights reserved.
//

import UIKit
class AkimaInterpolator {
  
  private let points: [CGPoint]
  private var m: [CGFloat]
  private var n: Int
  /*private var tr: [CGFloat]
  private var tl: [CGFloat]*/
  private var t: [CGFloat]
  
  private var a: [CGFloat]
  private var b: [CGFloat]
  private var c: [CGFloat]
  private var d: [CGFloat]
  
  init(points: [CGPoint]) {
    self.points = points
    n = points.count
    m = Array<CGFloat>(repeatElement(0.0, count: n + 3))
    //tr = Array<CGFloat>(repeatElement(0.0, count: n))
    //tl = Array<CGFloat>(repeatElement(0.0, count: n))
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
        /*let alpha = abs(m[i + 1] - m[i]) / NE
        tl[i] = m[i + 1] + alpha * (m[i + 2] - m[i + 1])
        tr[i] = tl[i]*/
        
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
  
  func interpolate(value x: CGFloat) -> CGFloat {
    var index = 0
    for (i, point) in points.enumerated() {
      if x > point.x {
        index = i
      }
      
    }
    let dx = x - points[index].x
    return a[index] + b[index] * dx + c[index] * dx * dx + d[index] * dx * dx * dx
  }
  
}
