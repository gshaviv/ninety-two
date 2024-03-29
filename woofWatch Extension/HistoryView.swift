//
//  DoseHistoryView.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2020.
//  Copyright © 2020 TivStudio. All rights reserved.
//

import SwiftUI
import Combine
import ObjectiveC




#if os(watchOS)
struct DoseHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo
    
    var body: some View {
        VStack {
            Text("Daily Dosages").font(Font.system(.headline))
            BarView(summary.data.daily.map {
                (values: [$0.date.isOnSameDay(as: Date()) ? 0 : $0.dose,
                          $0.date.isOnSameDay(as: Date()) ? $0.dose : 0],
                 marks: [$0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none, $0.date.isOnSameDay(as: Date()) ? [Summary.Marks.mark, Summary.Marks.bottomText] : Summary.Marks.bottomText])
            })
        }
    }
}

struct LowHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo
    
    var body: some View {
        VStack {
            Text("Daily Low Events").font(Font.system(.headline))
            BarView(summary.data.daily.map {
                (values: [$0.date.isOnSameDay(as: Date()) ? 0 : $0.lows,
                          $0.date.isOnSameDay(as: Date()) ? $0.lows : 0],
                 marks: [$0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none, $0.date.isOnSameDay(as: Date()) ? [Summary.Marks.mark, Summary.Marks.bottomText] : Summary.Marks.bottomText])
            })
        }
    }
}
class WatchLowsController: WKHostingController<AnyView> {
    override var body: AnyView {
        return LowHistoryView().environmentObject(summary).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        setTitle("Summary")
    }
}

class WatchDoseController: WKHostingController<AnyView> {
    override var body: AnyView {
        return DoseHistoryView().environmentObject(summary).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        setTitle("Summary")
    }
}

struct AveHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo
    
    var body: some View {
        VStack {
            Text("Daily Averages").font(Font.system(.headline))
            BarView(summary.data.daily.map {
                (values: [$0.date.isOnSameDay(as: Date()) ? 0 : rint($0.average),
                          $0.date.isOnSameDay(as: Date()) ? rint($0.average) : 0],
                 marks: [$0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none, $0.date.isOnSameDay(as: Date()) ? [Summary.Marks.mark, Summary.Marks.bottomText] : Summary.Marks.bottomText])
            })
        }
    }
}

class WatchAveHistoryController: WKHostingController<AnyView> {    
    override var body: AnyView {
        return AveHistoryView().environmentObject(summary).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        setTitle("Summary")
    }
}

struct RangeHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo
    
    var body: some View {
         VStack {
            Text("Daily Time Out of Range").font(Font.system(size: 15))
            BarView(summary.data.daily.map {
                (values: [$0.percentLow, $0.percentHigh],
                 marks: [$0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none, $0.date.isOnSameDay(as: Date()) ? [Summary.Marks.mark, Summary.Marks.bottomText] : Summary.Marks.bottomText])
            })
                .clustered()
                .colors([defaults[.color0].withAlphaComponent(0.4), defaults[.color5].withAlphaComponent(0.4)])
        }
    }
}
class WatchRangeHistoryController: WKHostingController<AnyView> {
    override var body: AnyView {
        return RangeHistoryView().environmentObject(summary).asAnyView
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        setTitle("Summary")
    }
}

#else
import WoofKit

extension UIView {
    static private var flag = false
    fileprivate func didScroll() -> Bool {
        if objc_getAssociatedObject(self, &UIView.flag) == nil {
            objc_setAssociatedObject(self, &UIView.flag, true, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return false
        }
        return true
    }
}
struct DoseHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo
    
    var body: some View {
        BarView(summary.data.daily.map {
            (values: [$0.date.isOnSameDay(as: Date()) ? 0 : $0.dose,
                      $0.date.isOnSameDay(as: Date()) ? $0.dose : 0],
             marks: [$0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none, $0.date.isOnSameDay(as: Date()) ? Summary.Marks.mark : Summary.Marks.none])
        })
    }
}

struct AveHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo
    
    var body: some View {
        BarView(summary.data.daily.map {
            (values: [$0.date.isOnSameDay(as: Date()) ? 0 : rint($0.average),
                      $0.date.isOnSameDay(as: Date()) ? rint($0.average) : 0],
             marks: [$0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none, $0.date.isOnSameDay(as: Date()) ? Summary.Marks.mark : Summary.Marks.none])
        })
    }
}

@discardableResult private func findScrollViewAndScrollToRight(_ view: UIView) -> Bool {
    if let sv = view as? UIScrollView {
        sv.contentOffset = CGPoint(x: sv.contentSize.width - sv.width, y: 0)
        return true
    }
    for v in view.subviews {
        if findScrollViewAndScrollToRight(v) {
            return true
        }
    }
    return false
}
class AveHistoryController: UIHostingController<AnyView> {
    init() {
        super.init(rootView: AveHistoryView().environmentObject(summary).asAnyView)
        title = "Daily Average History"
        overrideUserInterfaceStyle = .dark
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !view.didScroll() {
            findScrollViewAndScrollToRight(view)
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isMovingToParent {
            if let view: UIScrollView = view.typedChild() {
                view.isUserInteractionEnabled = true
                view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
            }
        }
    }
    
    @objc private func didTap(_ sender: UIGestureRecognizer) {
        TimeDisplay.respond(toTap: sender, in: self)
    }
}
struct LowHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo
    
    var body: some View {
        BarView(summary.data.daily.map {
            (values: [$0.date.isOnSameDay(as: Date()) ? 0 : $0.lows,
                      $0.date.isOnSameDay(as: Date()) ? $0.lows : 0],
             marks: $0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none)
        })
    }
}
class LowsHistoryController: UIHostingController<AnyView> {
    init() {
        super.init(rootView: LowHistoryView().environmentObject(summary).asAnyView)
        title = "Daily Lows History"
        overrideUserInterfaceStyle = .dark
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !view.didScroll() {
            findScrollViewAndScrollToRight(view)
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isMovingToParent {
            if let view: UIScrollView = view.typedChild() {
                view.isUserInteractionEnabled = true
                view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
            }
        }
    }
    
    @objc private func didTap(_ sender: UIGestureRecognizer) {
        TimeDisplay.respond(toTap: sender, in: self)
    }
}
class DoseHistoryController: UIHostingController<AnyView> {
    init() {
        super.init(rootView: DoseHistoryView().environmentObject(summary).asAnyView)
        title = "Total Daily Doseage"
        overrideUserInterfaceStyle = .dark
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !view.didScroll() {
            findScrollViewAndScrollToRight(view)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isMovingToParent {
            if let view: UIScrollView = view.typedChild() {
                view.isUserInteractionEnabled = true
                view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
            }
        }
    }
    
    @objc private func didTap(_ sender: UIGestureRecognizer) {
        TimeDisplay.respond(toTap: sender, in: self)
    }
}
struct RangeHistoryView: View {
    @EnvironmentObject var summary: SummaryInfo
    
    var body: some View {
        BarView(summary.data.daily.map {
            (values: [$0.percentLow, $0.percentHigh],
             marks: [$0.date.weekDay == 1 ? Summary.Marks.seperator : Summary.Marks.none, $0.date.isOnSameDay(as: Date()) ? [Summary.Marks.mark, Summary.Marks.bottomText] : Summary.Marks.bottomText])
        })
            .clustered()
            .colors([defaults[.color0].darker(by: 60), defaults[.color5].darker(by: 60)])
    }
}
class RangeHistoryController: UIHostingController<AnyView> {
    init() {
        super.init(rootView: RangeHistoryView().environmentObject(summary).asAnyView)
        title = "Daily Time Outside Range"
        overrideUserInterfaceStyle = .dark
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


enum TimeDisplay {
    static func respond(toTap sender: UIGestureRecognizer, in vc: UIViewController) {
        guard let sv = sender.view as? UIScrollView,
              let grandparent = vc.parent?.parent else {
            return
        }
        let loc = sender.location(in: sv)
        let ratio = 1 - loc.x / sv.contentSize.width
        let daysback = Int(ratio * CGFloat(summary.data.daily.count)) + 1
        guard daysback > 0 else {
            return
        }
        switch grandparent {
        case let ctr as HistoryViewController:
            ctr.displayDay = Date() - daysback.d
            
        case let ctr as ViewController:
            ctr.performSegue(withIdentifier: "history", sender: nil)
            if let hvc = grandparent.navigationController?.topViewController as? HistoryViewController {
                hvc.displayDay = Date() - daysback.d
                hvc.onSummaryVC = { [weak vc] nav in
                    guard let vc = vc else {
                        return
                    }
                    let tp = type(of: vc)
                    nav.pushViewController(tp.init(), animated: false)
                    vc.navigationController?.popToRootViewController(animated: false)
                }
            }
            
        default:
            break
        }
        
    }
}

extension RangeHistoryController {
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isMovingToParent {
            if let view: UIScrollView = view.typedChild() {
            view.isUserInteractionEnabled = true
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
            }
        }
    }
    
    @objc private func didTap(_ sender: UIGestureRecognizer) {
        TimeDisplay.respond(toTap: sender, in: self)
    }
}

extension UIView {
    func typedChild<T>() -> T? {
        for v in subviews {
            if let v = v as? T {
                return v
            } else if let v: T = v.typedChild() {
                return v
            }
        }
        return nil
    }
}

#endif

#if DEBUG
struct DoseHistoryView_Previews: PreviewProvider {
    static let summary = SummaryInfo(Summary(period: 30, actualPeriod: 30, timeInRange: Summary.TimeInRange(low: 30, inRange: 30, high: 30), maxLevel: 246, minLevel: 45, average: 125, a1c: Summary.EA1C(value: 6.1, range: 0.1), low: Summary.Low(count: 20, median: 45), atdd: 20.1, timeInLevel: [5,5,40,40,40,10,10], daily:
        [
            Summary.Daily(average: 120.0, dose: 20, lows: 0, date: Date() - 7.d, percentLow: 2, percentHigh: 8),
            Summary.Daily(average: 120.5, dose: 18, lows: 1, date: Date() - 6.d, percentLow: 0, percentHigh: 7),
            Summary.Daily(average: 123.0, dose: 22, lows: 0, date: Date() - 5.d, percentLow: 0, percentHigh: 0),
            Summary.Daily(average: 120.0, dose: 17, lows: 1, date: Date() - 4.d, percentLow: 1, percentHigh: 8),
            Summary.Daily(average: 113.4, dose: 16, lows: 2, date: Date() - 3.d, percentLow: 2, percentHigh: 7),
            Summary.Daily(average: 117.4, dose: 19, lows: 0, date: Date() - 2.d, percentLow: 3, percentHigh: 6),
            Summary.Daily(average: 114.4, dose: 21, lows: 0, date: Date() - 1.d, percentLow: 2, percentHigh: 0),
            Summary.Daily(average: 120.0, dose: 8, lows: 0, date: Date(), percentLow: 1, percentHigh: 8)
        ],
                                             date: Date()
    ))
    
    static var previews: some View {
        DoseHistoryView().environmentObject(summary)
    }
}
#endif
