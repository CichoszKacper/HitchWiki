//
//  SpotButton.swift
//  HitchWiki
//
//  A pill under a hitchhiking option that shows its spot on a map.
//

import SwiftUI

struct SpotButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Label(self.title, systemImage: "hand.thumbsup.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.14), in: .capsule)
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.pressable)
    }
}

#Preview {
    SpotButton(title: "Show spot on map") {}
}
