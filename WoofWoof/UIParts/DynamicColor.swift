//
//  DynamicColor.swift
//  WoofWoof
//
//  Created by Guy on 29/09/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import SwiftUI

public struct DynamicColor: View {
    var light: Color
    var dark: Color
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    
    public var body: some View {
        switch colorScheme {
        case .dark:
            return dark
        default:
            return light
        }
    }
}

