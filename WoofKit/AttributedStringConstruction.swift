//
//  AttributedStringConstruction.swift
//  houzz
//
//  Created by Guy on 22/01/2017.
//
//

import Foundation
import UIKit



extension String {
    public var styled: NSMutableAttributedString {
        return NSMutableAttributedString(string: self).color(.black)
    }
}

extension NSMutableAttributedString {
    public static func += (left: NSMutableAttributedString, right: NSAttributedString) {
        left.append(right)
    }

    public static func += (left: NSMutableAttributedString, right: String) {
        left.append(NSAttributedString(string: right))
    }

    @discardableResult public final func color(_ color: UIColor, range: NSRange? = nil) -> NSMutableAttributedString {
        addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: range ?? NSMakeRange(0, length))
        return self
    }

    @discardableResult public final func underline(_ style: NSUnderlineStyle, range: NSRange? = nil) -> NSMutableAttributedString {
        addAttribute(NSAttributedString.Key.underlineStyle, value: style.rawValue, range: range ?? NSMakeRange(0, length))
        return self
    }

    @discardableResult public final func strikethrough(_ style: NSUnderlineStyle, range: NSRange? = nil) -> NSMutableAttributedString {
        addAttribute(NSAttributedString.Key.strikethroughStyle, value: style.rawValue, range: range ?? NSMakeRange(0, length))
        return self
    }

    @discardableResult public final func systemFont(_ weight: UIFont.Weight = .regular, size: CGFloat, range: NSRange? = nil) -> NSMutableAttributedString {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        addAttribute(NSAttributedString.Key.font, value: font, range: range ?? NSMakeRange(0, length))
        return self
    }

    @discardableResult public final func font(_ font: UIFont?, range: NSRange? = nil) -> NSMutableAttributedString {
        guard let font = font else {
            return self
        }
        addAttribute(NSAttributedString.Key.font, value: font, range: range ?? NSMakeRange(0, length))
        return self
    }

    @discardableResult public final func preferredFont(_ textStyle: UIFont.TextStyle, range: NSRange? = nil) -> NSMutableAttributedString {
        let font = UIFont.preferredFont(forTextStyle: textStyle)
        addAttribute(NSAttributedString.Key.font, value: font, range: range ?? NSMakeRange(0, length))
        return self
    }

    @discardableResult public final func style(_ style: UIFont.TextStyle, traits: UIFontDescriptor.SymbolicTraits = [], range: NSRange? = nil) -> NSMutableAttributedString {
        var fd = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        if !traits.isEmpty, let fdm = fd.withSymbolicTraits(traits) {
            fd = fdm
        }
        let font = UIFont(descriptor: fd, size: 0)
        addAttribute(NSAttributedString.Key.font, value: font, range: range ?? NSMakeRange(0, length))
        return self
    }

    @discardableResult public final func sizeFactor(_ factor: CGFloat, min: CGFloat? = nil, max: CGFloat? = nil, range: NSRange? = nil) -> NSMutableAttributedString {
        let font = (attribute(NSAttributedString.Key.font, at: range?.location ?? 0, effectiveRange: nil) as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        let fd = font.fontDescriptor
        var ps = fd.pointSize * factor
        if let min = min, ps < min {
            ps = min
        } else if let max = max, ps > max {
            ps = max
        }
        let fontMod = UIFont(descriptor: fd.withSize(ps), size: 0)
        addAttribute(NSAttributedString.Key.font, value: fontMod, range: range ?? NSMakeRange(0, length))
        return self
    }

    @discardableResult public final func traits(_ trait: UIFontDescriptor.SymbolicTraits, range: NSRange? = nil) -> NSMutableAttributedString {
        let font = (attribute(NSAttributedString.Key.font, at: range?.location ?? 0, effectiveRange: nil) as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        let fd = font.fontDescriptor
        if let fdMod = fd.withSymbolicTraits(trait) {
            let fontMod = UIFont(descriptor: fdMod, size: 0)
            addAttribute(NSAttributedString.Key.font, value: fontMod, range: range ?? NSMakeRange(0, length))
        }
        return self
    }

    @discardableResult public final func text(alignment: NSTextAlignment = .natural, paragraphSpacing: CGFloat = 0, lineBreakMode: NSLineBreakMode = .byTruncatingTail, lineHeightMultiple: CGFloat = 1, range: NSRange? = nil) -> NSMutableAttributedString {
        let pStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        pStyle.alignment = alignment
        pStyle.paragraphSpacing = paragraphSpacing
        pStyle.lineBreakMode = lineBreakMode
        pStyle.lineHeightMultiple = lineHeightMultiple
        addAttribute(NSAttributedString.Key.paragraphStyle, value: pStyle, range: range ?? NSMakeRange(0, length))
        return self
    }

    @discardableResult public final func link(_ urlStr: String, range: NSRange? = nil) -> NSMutableAttributedString {
        addAttribute(NSAttributedString.Key(rawValue: "href"), value: urlStr, range: range ?? NSMakeRange(0, length))
        return self
    }
}

public func +(lhs: NSAttributedString, rhs: NSAttributedString) -> NSMutableAttributedString {
    let result = NSMutableAttributedString(attributedString: lhs)
    result.append(rhs)
    return result
}

public func +(lhs: NSAttributedString, rhs: String) -> NSMutableAttributedString {
    let result = NSMutableAttributedString(attributedString: lhs)
    result.append(NSAttributedString(string: rhs))
    return result
}
