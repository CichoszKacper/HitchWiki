//
//  Shimmer.swift
//  HitchWiki
//
//  A light sweeping across placeholder shapes while content loads.
//

import SwiftUI

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: self.phase * geometry.size.width * 1.6)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !self.reduceMotion else {
                    return
                }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    self.phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        self.modifier(Shimmer())
    }
}
