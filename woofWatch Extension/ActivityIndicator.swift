//
//  CircularActivityIndicator.swift
//  woofWatch Extension
//
//  Created by Guy on 19/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import SwiftUI

struct ActivityIndicator: View {
    @State var spinCircle = false
    private(set) var size: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.2, to: 1)
                .stroke(Color.red, lineWidth:3)
                .frame(width:size, height:size)
                .rotationEffect(.degrees(spinCircle ? 0 : -360), anchor: .center)
                .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false))
        }
        .onAppear {
            self.spinCircle = true
        }
    }
}

#if DEBUG
struct ActivityIndicator_Preview: PreviewProvider {
    static var previews: some View {
        ActivityIndicator(size: 30)
    }
}
#endif
