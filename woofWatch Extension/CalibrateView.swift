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

typealias Action = PassthroughSubject<Void,Never>

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
            .foregroundColor(text.wrappedValue.isEmpty ? Color.secondary : Color.primary)
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
            .frame(width: self.width, height: self.height)

    }
}

struct CalibrateView: View {
    @State var text: String = ""
    let dismiss: Action
    
    var body: some View {
        GeometryReader { screen in
            VStack(spacing: 2.0) {
                Text(self.text)
                    .frame(minWidth: screen.size.width, minHeight: 36)
                    .background(Color(red: 0.15, green: 0.15, blue: 0.15)
                        .border(Color.white))
                    .foregroundColor(Color.yellow)
                    .font(.title)
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
                        if let v = Double(self.text), v > 65 && v < 185 {
                            WCSession.default.sendMessage(["op":["calibrate"],"value":v], replyHandler: { _ in }, errorHandler: { _ in })
                            self.dismiss.send()
                        }
                    }
                    Key(0,self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                    Delete(self.$text, width: (screen.size.width - 4) / 3, height: (screen.size.height - 44 - 21) / 4)
                }
            }.onAppear {
                WCSession.default.sendMessage(["op":["read"]], replyHandler: { _ in }, errorHandler: { _ in })
            }
        }.edgesIgnoringSafeArea([.bottom, .leading, .trailing])
    }
}

class CalibrationController: WKHostingController<AnyView> {
    var dismissListener: AnyCancellable?
    override var body: AnyView {
        let action = Action()
        dismissListener = action.sink(receiveValue: {
            self.goAway()
        })
        return CalibrateView(dismiss: action).asAnyView
    }
    
    @objc func goAway() {
        dismiss()
    }
}


struct CalibrateView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CalibrateView(dismiss: Action())
        }
    }
}
