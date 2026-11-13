//
//  StaggeredAppear.swift
//  HitchWiki
//
//  Fades and slides a view in when it appears, a little later for each index,
//  so a list of cards arrives one after another.
//

import SwiftUI

struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(self.isVisible ? 1 : 0)
            .offset(y: self.isVisible || self.reduceMotion ? 0 : 28)
            .onAppear {
                withAnimation(Theme.spring.delay(Double(min(self.index, 8)) * 0.06)) {
                    self.isVisible = true
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int) -> some View {
        self.modifier(StaggeredAppear(index: index))
    }
}
