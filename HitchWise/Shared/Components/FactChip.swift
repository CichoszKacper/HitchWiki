//
//  FactChip.swift
//  HitchWiki
//
//  A small card with an icon, a label and a value, e.g. CAPITAL / Warsaw.
//

import SwiftUI

struct FactChip: View {
    let label: String
    let value: String
    let systemImage: String
    /// Shows an arrow: the chip opens something when tapped.
    var isLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(self.label.uppercased(), systemImage: self.systemImage)
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(self.value)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if self.isLink {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
        .cardStyle(cornerRadius: Theme.smallCornerRadius)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack {
        FactChip(label: "Capital", value: "Warsaw", systemImage: "building.columns.fill", isLink: true)
        FactChip(label: "Currency", value: "Złoty (PLN)", systemImage: "banknote.fill")
    }
    .padding()
    .background(Theme.background)
}
