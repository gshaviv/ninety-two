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
    private var cancel: AnyCancellable?
    @ObservedObject var imageGenerator: ImageGenerator
    
    var body: some View {
        Image(uiImage: imageGenerator.image)
            .cornerRadius(6)
    }
    
    init(state: AppState, size: CGSize) {
        self.imageGenerator = ImageGenerator(size: size, state: state)
    }
}
