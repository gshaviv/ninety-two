//
//  BalancedHStack.swift
//  SwiftUIComponents
//
//  Created by Guy on 27/09/2019.
//  Copyright © 2019 Guy. All rights reserved.
//

import SwiftUI

struct BalancedHStack: View {
    var views: [AnyView]
    var spacing: CGFloat = 0
    var alignment: VerticalAlignment

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: self.alignment, spacing: self.spacing) {
                ForEach(0 ..< self.views.count) { index in
                    self.views[index].frame(width: (geometry.size.width - CGFloat(self.views.count - 1) * self.spacing) / CGFloat(self.views.count) , alignment: .center)
                }
            }
        }
    }
    
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat = 0, _ views: [AnyView]) {
        self.views = views
        self.alignment = alignment
        self.spacing = spacing
    }
    
    public init<Data: RandomAccessCollection,  Content: View>(_ data: Data, alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: (Data.Element) -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.views = data.map { content($0).asAnyView }
    }
    
    public init<Content: View>(_ data: Range<Int>, alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: (Int) -> Content)  {
        self.alignment = alignment
        self.spacing = spacing
        self.views = data.map { content($0).asAnyView }
    }
    
    public init<A: View>(alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: () -> A) {
        self.alignment = alignment
        self.spacing = spacing
        self.views = [AnyView(content())]
    }
        
    public init<V1: View, V2: View>(alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: () -> TupleView<(V1, V2)>) {
        self.alignment = alignment
        self.spacing = spacing
        let views = content().value
        self.views = [AnyView(views.0), AnyView(views.1)]
    }
  
    public init<V1: View, V2: View, V3: View>(alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: () -> TupleView<(V1, V2, V3)>) {
        self.alignment = alignment
        self.spacing = spacing
        let views = content().value
        self.views = [AnyView(views.0), AnyView(views.1), AnyView(views.2)]
    }
   
    public init<V1: View, V2: View, V3: View, V4: View>(alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: () -> TupleView<(V1, V2, V3, V4)>) {
        self.alignment = alignment
        self.spacing = spacing
        let views = content().value
        self.views = [AnyView(views.0), AnyView(views.1), AnyView(views.2), AnyView(views.3)]
    }
    
    public init<V1: View, V2: View, V3: View, V4: View, V5: View>(alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: () -> TupleView<(V1, V2, V3, V4, V5)>) {
        self.alignment = alignment
        self.spacing = spacing
        let views = content().value
        self.views = [AnyView(views.0), AnyView(views.1), AnyView(views.2), AnyView(views.3), AnyView(views.4)]
    }
    
    public init<V1: View, V2: View, V3: View, V4: View, V5: View, V6: View>(alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: () -> TupleView<(V1, V2, V3, V4, V5, V6)>) {
        self.alignment = alignment
        self.spacing = spacing
        let views = content().value
        self.views = [AnyView(views.0), AnyView(views.1), AnyView(views.2), AnyView(views.3), AnyView(views.4), AnyView(views.5)]
    }
    
    public init<V1: View, V2: View, V3: View, V4: View, V5: View, V6: View, V7: View>(alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: () -> TupleView<(V1, V2, V3, V4, V5, V6, V7)>) {
        self.alignment = alignment
        self.spacing = spacing
        let views = content().value
        self.views = [AnyView(views.0), AnyView(views.1), AnyView(views.2), AnyView(views.3), AnyView(views.4), AnyView(views.5), AnyView(views.6)]
    }
    
    public init<V1: View, V2: View, V3: View, V4: View, V5: View, V6: View, V7: View, V8: View>(alignment: VerticalAlignment = .center, spacing: CGFloat = 0, @ViewBuilder content: () -> TupleView<(V1, V2, V3, V4, V5, V6, V7, V8)>) {
        self.alignment = alignment
        self.spacing = spacing
        let views = content().value
        self.views = [AnyView(views.0), AnyView(views.1), AnyView(views.2), AnyView(views.3), AnyView(views.4), AnyView(views.5), AnyView(views.6), AnyView(views.7)]
    }
    
 
    
}

#if DEBUG
struct BalancedHStack_Previews: PreviewProvider {
    static var platform: PreviewPlatform? = .iOS
    static var previews: some View {
        Group {
            BalancedHStack(spacing: 6) {
                Rectangle().aspectRatio(1, contentMode: .fit)
                Circle().fill(Color.red)
                Rectangle().fill(Color.blue).aspectRatio(1, contentMode: .fit)
            }
            BalancedHStack([1,2,4], spacing: 10) { idx in
                ZStack {
                    Circle().fill(Color.orange)
                    Text("\(idx)").font(.title)
                }
            }
            BalancedHStack(0 ..< 4, spacing: 10) { idx in
                ZStack {
                    Circle().fill(Color.orange)
                    Text("\(idx)").font(.title)
                }
            }
        }
    }
}
#endif
