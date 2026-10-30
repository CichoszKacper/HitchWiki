//
//  SectionCardView.swift
//  HitchWiki
//
//  One top-level section of a page as a collapsible card, with its subsections inside.
//

import SwiftUI

struct SectionCardView: View {
    let card: SectionCard
    let content: PageContent
    @Binding var isExpanded: Bool
    var onShowSpot: (PageSpot) -> Void

    var body: some View {
        CollapsibleCard(isExpanded: self.$isExpanded) {
            HStack(spacing: 14) {
                Image(systemName: self.card.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.gradient, in: .rect(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.card.heading.title)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.leading)
                    if let summary = self.card.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                SubsectionView(section: self.card.heading, depth: 0,
                               spots: self.content.spots(in: self.card.heading), onShowSpot: self.onShowSpot)
                ForEach(self.card.subsections) { section in
                    SubsectionView(section: section, depth: section.level - self.card.heading.level,
                                   spots: self.content.spots(in: section), onShowSpot: self.onShowSpot)
                }
            }
        }
    }
}

/// A heading (unless it's the card's own) with its text and spots.
struct SubsectionView: View {
    let section: PageSection
    /// 0 for the card's own text, 1 for its direct subsections, 2 for theirs...
    let depth: Int
    let spots: [PageSpot]
    var onShowSpot: (PageSpot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if self.depth > 0 && !self.section.title.isEmpty {
                LinkedText(self.section.title, links: self.section.titleLinks)
                    .font(self.depth == 1 ? .headline : .subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            if !self.section.text.isEmpty {
                LinkedText(self.section.text, links: self.section.links)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(.primary.opacity(0.88))
                    .textSelection(.enabled)
            }
            if !self.spots.isEmpty {
                // Wraps onto more lines when there are many spots
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(self.spots.enumerated()), id: \.element.id) { index, spot in
                        SpotButton(title: self.spots.count == 1 ? "Show on map" : "Spot \(index + 1)") {
                            self.onShowSpot(spot)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, self.depth > 1 ? 14 : 0)
        .overlay(alignment: .leading) {
            if self.depth > 1 {
                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 3)
            }
        }
    }
}
