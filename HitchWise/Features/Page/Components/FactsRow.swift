//
//  FactsRow.swift
//  HitchWiki
//
//  The infobox as a row of chips that scroll sideways. Chips that name another page open it.
//

import SwiftUI

struct FactsRow: View {
    let facts: [Fact]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(self.facts) { fact in
                    self.chip(for: fact)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .opacity(phase.isIdentity ? 1 : 0.5)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Theme.screenPadding, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func chip(for fact: Fact) -> some View {
        if let page = fact.linkedPage {
            NavigationLink(value: PageRoute(title: page)) {
                FactChip(label: fact.label, value: fact.value, systemImage: fact.systemImage, isLink: true)
            }
            .buttonStyle(.pressable)
        } else {
            FactChip(label: fact.label, value: fact.value, systemImage: fact.systemImage)
        }
    }
}
