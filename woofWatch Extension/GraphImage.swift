//
//  GraphImage.swift
//  woofWatch Extension
//
//  Created by Guy on 19/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

struct GraphImage: View {
    @State private var image: UIImage? = nil
    @State private var imageGenerator = ImageGenerator()
    private var cancel: AnyCancellable?
    private var state: AppState
    private var size: CGSize
    
    var body: some View {
        self.imageGenerator.size = size
        self.imageGenerator.observe(state: state)
        return Image(uiImage: imageGenerator.image)
            .cornerRadius(6)
    }
    
    init(state: AppState, size: CGSize) {
        self.state = state
        self.size = size
    }
}
