//
//  EFHSBView.swift
//  EFColorPicker
//
//  Created by EyreFree on 2017/9/29.
//
//  Copyright (c) 2017 EyreFree <eyrefree@eyrefree.org>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import UIKit

// The view to edit HSB color components.
@IBDesignable
public class EFHSBView: UIView, EFColorView, UITextFieldDelegate {

    let EFColorSampleViewHeight: CGFloat = 30.0
    let EFViewMargin: CGFloat = 20.0
    let EFColorWheelDimension: CGFloat = 200.0

    private let colorWheel: EFColorWheelView = EFColorWheelView()
    let brightnessView: EFColorComponentView = EFColorComponentView()
    private let colorSample: UIView = UIView()

    private var colorComponents: HSB = HSB(1, 1, 1, 1)
    private var layoutConstraints: [NSLayoutConstraint] = []

    weak public var delegate: EFColorViewDelegate?

    public var isTouched: Bool {
        if self.colorWheel.isTouched {
            return true
        }

        if self.brightnessView.isTouched {
            return true
        }

        return false
    }

    public var color: UIColor {
        get {
            return UIColor(
                hue: colorComponents.hue,
                saturation: colorComponents.saturation,
                brightness: colorComponents.brightness,
                alpha: colorComponents.alpha
            )
        }
        set {
            colorComponents = EFRGB2HSB(rgb: EFRGBColorComponents(color: newValue))
            self.reloadData()
        }
    }

    public override func awakeFromNib() {
        super.awakeFromNib()
        colorWheel.backgroundColor = backgroundColor
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.ef_baseInit()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.ef_baseInit()
    }

    func reloadData() {
        colorSample.backgroundColor = self.color
        colorSample.accessibilityValue = EFHexStringFromColor(color: self.color)
        self.ef_reloadViewsWithColorComponents(colorComponents: colorComponents)
        self.colorWheel.display(self.colorWheel.layer)
    }

    override public func updateConstraints() {
        self.ef_updateConstraints()
        super.updateConstraints()
    }

    // MARK:- Private methods
    private func ef_baseInit() {
        self.accessibilityLabel = "hsb_view"

        colorSample.accessibilityLabel = "color_sample"
        colorSample.layer.borderColor = UIColor.black.cgColor
        colorSample.layer.borderWidth = 0.5
        colorSample.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(colorSample)

        colorWheel.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(colorWheel)

        brightnessView.title = NSLocalizedString("Brightness", comment: "")
        brightnessView.maximumValue = EFHSBColorComponentMaxValue
        brightnessView.format = "%.2f"
        brightnessView.translatesAutoresizingMaskIntoConstraints = false
        brightnessView.setColors(colors: [UIColor.black, UIColor.white])
        self.addSubview(brightnessView)

        colorWheel.addTarget(
            self, action: #selector(ef_colorDidChangeValue(sender:)), for: UIControl.Event.valueChanged
        )
        brightnessView.addTarget(
            self, action: #selector(ef_brightnessDidChangeValue(sender:)), for: UIControl.Event.valueChanged
        )

        self.setNeedsUpdateConstraints()
    }

    private func ef_updateConstraints() {
        // remove all constraints first
        if !layoutConstraints.isEmpty {
            self.removeConstraints(layoutConstraints)
        }

        layoutConstraints = UIUserInterfaceSizeClass.compact == self.traitCollection.verticalSizeClass
            ? self.ef_constraintsForCompactVerticalSizeClass()
            : self.ef_constraintsForRegularVerticalSizeClass()

        self.addConstraints(layoutConstraints)
    }

    private func ef_constraintsForRegularVerticalSizeClass() -> [NSLayoutConstraint] {
        let metrics = [
            "margin" : EFViewMargin,
            "height" : EFColorSampleViewHeight,
            "color_wheel_dimension" : EFColorWheelDimension
        ]
        let views = [
            "colorSample" : colorSample,
            "colorWheel" : colorWheel,
            "brightnessView" : brightnessView
        ]

        var layoutConstraints: [NSLayoutConstraint] = []
        let visualFormats = [
            "H:|-margin-[colorSample]-margin-|",
            "H:|-margin-[colorWheel(>=color_wheel_dimension)]-margin-|",
            "H:|-margin-[brightnessView]-margin-|",
            "V:|-margin-[colorSample(height)]-margin-[colorWheel]-margin-[brightnessView]-(>=margin@250)-|"
        ]
        for visualFormat in visualFormats {
            layoutConstraints.append(
                contentsOf: NSLayoutConstraint.constraints(
                    withVisualFormat: visualFormat,
                    options: NSLayoutConstraint.FormatOptions(rawValue: 0),
                    metrics: metrics,
                    views: views
                )
            )
        }
        layoutConstraints.append(
            NSLayoutConstraint(
                item: colorWheel,
                attribute: NSLayoutConstraint.Attribute.width,
                relatedBy: NSLayoutConstraint.Relation.equal,
                toItem: colorWheel,
                attribute: NSLayoutConstraint.Attribute.height,
                multiplier: 1,
                constant: 0)
        )
        return layoutConstraints
    }

    private func ef_constraintsForCompactVerticalSizeClass() -> [NSLayoutConstraint] {
        let metrics = [
            "margin" : EFViewMargin,
            "height" : EFColorSampleViewHeight,
            "color_wheel_dimension" : EFColorWheelDimension
        ]
        let views = [
            "colorSample" : colorSample,
            "colorWheel" : colorWheel,
            "brightnessView" : brightnessView
        ]

        var layoutConstraints: [NSLayoutConstraint] = []
        let visualFormats = [
            "H:|-margin-[colorSample]-margin-|",
            "H:|-margin-[colorWheel(>=color_wheel_dimension)]-margin-[brightnessView]-(margin@500)-|",
            "V:|-margin-[colorSample(height)]-margin-[colorWheel]-(margin@500)-|"
        ]
        for visualFormat in visualFormats {
            layoutConstraints.append(
                contentsOf: NSLayoutConstraint.constraints(
                    withVisualFormat: visualFormat,
                    options: NSLayoutConstraint.FormatOptions(rawValue: 0),
                    metrics: metrics,
                    views: views
                )
            )
        }
        layoutConstraints.append(
            NSLayoutConstraint(
                item: colorWheel,
                attribute: NSLayoutConstraint.Attribute.width,
                relatedBy: NSLayoutConstraint.Relation.equal,
                toItem: colorWheel,
                attribute: NSLayoutConstraint.Attribute.height,
                multiplier: 1,
                constant: 0)
        )
        layoutConstraints.append(
            NSLayoutConstraint(
                item: brightnessView,
                attribute: NSLayoutConstraint.Attribute.centerY,
                relatedBy: NSLayoutConstraint.Relation.equal,
                toItem: self,
                attribute: NSLayoutConstraint.Attribute.centerY,
                multiplier: 1,
                constant: 0)
        )
        return layoutConstraints
    }

    private func ef_reloadViewsWithColorComponents(colorComponents: HSB) {
        colorWheel.hue = colorComponents.hue
        colorWheel.saturation = colorComponents.saturation
        colorWheel.brightness = colorComponents.brightness
        self.ef_updateSlidersWithColorComponents(colorComponents: colorComponents)
    }

    private func ef_updateSlidersWithColorComponents(colorComponents: HSB) {
        brightnessView.value = colorComponents.brightness
    }

    @objc private func ef_colorDidChangeValue(sender: EFColorWheelView) {
        colorComponents.hue = sender.hue
        colorComponents.saturation = sender.saturation
        self.delegate?.colorView(self, didChangeColor: self.color)
        self.reloadData()
    }

    @objc private func ef_brightnessDidChangeValue(sender: EFColorComponentView) {
        colorComponents.brightness = sender.value
        self.colorWheel.brightness = sender.value
        self.delegate?.colorView(self, didChangeColor: self.color)
        self.reloadData()
    }
}
