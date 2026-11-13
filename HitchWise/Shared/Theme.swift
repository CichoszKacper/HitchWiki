//
//  Theme.swift
//  HitchWiki
//
//  Shared sizes, animations and the card surface used across the app.
//  The accent colour lives in Assets.xcassets/AccentColor.
//

import SwiftUI

enum Theme {
    static let cornerRadius: CGFloat = 24
    static let smallCornerRadius: CGFloat = 18
    static let cardPadding: CGFloat = 18
    static let screenPadding: CGFloat = 16

    /// Default spring for expanding, appearing and moving things.
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)
    /// Quick spring for button presses.
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)

    static let background = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
}

extension View {
    /// The rounded, softly shadowed surface used for cards and chips.
    func cardStyle(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        self
            .background(Theme.cardBackground, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
    }
}

/// A screen's big title, for tabs that hide the navigation bar: the same look as a large
/// navigation title, without the empty bar above it.
struct ScreenTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: self.text)
            .font(.largeTitle.bold())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// For screens without a navigation bar: paints the strip behind the status bar so content
    /// scrolling up under the clock stays readable.
    func statusBarBackground(_ color: Color = Theme.background) -> some View {
        self.safeAreaInset(edge: .top, spacing: 0) {
            // A background ignores the safe area, so this zero-height view fills the status bar strip.
            Color.clear
                .frame(height: 0)
                .background(color)
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later, a translucent material before that.
    @ViewBuilder
    func glassBackground(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
