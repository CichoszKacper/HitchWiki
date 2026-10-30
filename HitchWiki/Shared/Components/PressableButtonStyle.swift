//
//  PressableButtonStyle.swift
//  HitchWiki
//
//  Shrinks a little while pressed and springs back, for cards and chips that act as buttons.
//

import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? self.scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
