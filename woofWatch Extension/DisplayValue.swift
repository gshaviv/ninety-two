//
//  DisplayValue.swift
//  woofWatch Extension
//
//  Created by Guy on 04/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import Foundation
import WatchKit

struct DisplayValue {
    let date: Date
    let string: String
    var image: UIImage {
        let attr = NSAttributedString(string: string, attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 24)])
        let size = attr.size()
        UIGraphicsBeginImageContextWithOptions(size, true, WKInterfaceDevice.current().screenScale)
        attr.draw(in: CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
    }
}
