//
//  CalibrateView.swift
//  WoofWoof
//
//  Created by Guy on 01/10/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import SwiftUI
import WatchConnectivity
import Combine

typealias Action<T> = PassthroughSubject<T,Never>

private struct Key: View {
    let value: String
    var text: Binding<String>
    let width: CGFloat
    let height: CGFloat

    init(_ n:Int, _ t: Binding<String>, width: CGFloat, height: CGFloat) {
        value = "\(n)"
        text = t
        self.width = width
        self.height = height
    }
    var body: some View {
        Text(value)
            .frame(width: self.width, height: self.height)
            .background(Color(red: 0.2, green: 0.2, blue: 0.2))
            .cornerRadius(3)
            .contentShape(Rectangle())
            .onTapGesture {
            self.text.wrappedValue +=  self.value
        }
    }
}

private struct Delete: View {
    var text: Binding<String>
    let width: CGFloat
    let height: CGFloat
    init(_ t: Binding<String>, width: CGFloat, height: CGFloat) {
        text = t
        self.width = width
        self.height = height
    }
    var body: some View {
        Image(systemName: "delete.left")
            .frame(width: self.width, height: self.height)
            .disabled(text.wrappedValue.isEmpty)
            .cornerRadius(3)
            .foregroundColor(text.wrappedValue.isEmpty ? Color.secondary : Color.primary)
            .contentShape(Rectangle())
            .onTapGesture {
                self.text.wrappedValue = self.text.wrappedValue[0 ..< (self.text.wrappedValue.count - 1)]
        }
    }
}

private struct Return: View {
    var text: Binding<String>
    let width: CGFloat
    let height: CGFloat
    init(_ t: Binding<String>, width: CGFloat, height: CGFloat) {
        text = t
        self.width = width
        self.height = height
    }
    var body: some View {
        Image(systemName: "return")
            .disabled(text.wrappedValue.isEmpty)
            .foregroundColor(text.wrappedValue.isEmpty ? Color.secondary : Color.primary)
            .cornerRadius(3)
            .frame(width: self.width, height: self.height)
            .contentShape(Rectangle())
    }
}

struct CalibrateView: View {
    @State var text: String = ""
    let dismiss: Action<Void>
    let title: Action<String>
    
    var body: some View {
        title.send(self.text)
        return GeometryReader { screen in
            VStack(spacing: 2.0) {
//                Spacer(minLength: 1)
//                Text(self.text)
//                    .frame(minWidth: screen.size.width, minHeight: 24)
//                    .background(Color(red: 0.15, green: 0.15, blue: 0.15)
//                        .border(Color.white))
//                    .foregroundColor(self.textError ? Color.red : Color.yellow)
//                    .font(Font.system(size: 18, weight: .medium))
                HStack(spacing: 2.0) {
                    Key(1,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                    Key(2,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                    Key(3,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                }
                HStack(spacing: 2.0) {
                    Key(4,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                    Key(5,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                    Key(6,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                }
                HStack(spacing: 2.0) {
                    Key(7,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                    Key(8,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                    Key(9,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                }
                HStack(spacing: 2.0) {
                    Return(self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4).onTapGesture {
                        if let v = Double(self.text), v > 65 && v < 200 {
                            WCSession.default.sendMessage(["op":["calibrate"],"value":v], replyHandler: { _ in }, errorHandler: { _ in })
                            self.dismiss.send()
                        } else {
                            self.title.send("\(self.text)x")
                            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(1)) {
                                self.title.send(self.text)
                            }
                        }
                    }
                    Key(0,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                    Delete(self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                }
            }.onAppear {
                WCSession.default.sendMessage(["op":["read"]], replyHandler: { _ in }, errorHandler: { _ in })
            }
        }.edgesIgnoringSafeArea(.all)
    }
}

class CalibrationController: WKHostingController<AnyView> {
    var dismissListener: AnyCancellable?
    var titleListener: AnyCancellable?
    override var body: AnyView {
        let action = Action<Void>()
        dismissListener = action.sink(receiveValue: {
            self.goAway()
        })
        let titleAction = Action<String>()
        titleListener = titleAction.sink(receiveValue: { (value) in
            self.setTitle("Cancel     \(value)")
        })
        return CalibrateView(dismiss: action, title: titleAction).asAnyView
    }
    
    override var contentSafeAreaInsets: UIEdgeInsets { .zero }
    
    @objc func goAway() {
        dismiss()
    }
}


struct CalibrateView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CalibrateView(dismiss: Action<Void>(), title: Action<String>())
        }
    }
}
