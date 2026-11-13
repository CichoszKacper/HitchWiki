//
//  ClusterBubble.swift
//  HitchWiki
//
//  A round badge with the number of points in a cluster. Bigger clusters get bigger bubbles;
//  it pops in with a spring when the map regroups.
//

import SwiftUI

struct ClusterBubble: View {
    let count: Int
    let tint: Color

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat {
        CGFloat(min(62.0, 34.0 + log2(Double(max(self.count, 2))) * 4.5))
    }

    private var label: String {
        self.count < 1000 ? "\(self.count)" : String(format: "%.1fk", Double(self.count) / 1000)
    }

    var body: some View {
        Text(self.label)
            .font(.system(size: self.diameter * 0.36, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: self.diameter, height: self.diameter)
            .background(self.tint.gradient, in: .circle)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .background(Circle().fill(self.tint.opacity(0.22)).padding(-6))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            .scaleEffect(self.isVisible || self.reduceMotion ? 1 : 0.3)
            .opacity(self.isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
                    self.isVisible = true
                }
            }
            .accessibilityLabel("\(self.count) places")
    }
}

#Preview {
    HStack(spacing: 24) {
        ClusterBubble(count: 2, tint: .accentColor)
        ClusterBubble(count: 37, tint: .blue)
        ClusterBubble(count: 1400, tint: .indigo)
    }
    .padding()
}
