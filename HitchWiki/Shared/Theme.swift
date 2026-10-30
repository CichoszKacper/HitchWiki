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
