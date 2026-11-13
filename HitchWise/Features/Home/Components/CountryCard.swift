//
//  CountryCard.swift
//  HitchWiki
//
//  "You're in Poland": the country the user is in, on glossy black with an orange edge, with its flag,
//  the start of its hitchhiking section, a few numbers and the basics (capital, language, money).
//

import SwiftUI

struct CountryCard: View {
    let country: CountryOverview

    private static let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius + 4, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.header

            if let summary = self.country.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            self.stats

            if !self.facts.isEmpty {
                self.factsPanel
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                // Glossy black: deep black with a lift at the top...
                LinearGradient(colors: [Color(white: 0.17), Color(white: 0.03)], startPoint: .top, endPoint: .bottom)
                // ...and a sheen over the top half that ends in a soft line, like lacquer.
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.16), location: 0),
                    .init(color: .white.opacity(0.05), location: 0.42),
                    .init(color: .clear, location: 0.48)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(Self.shape)
        .overlay {
            Self.shape
                .strokeBorder(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5)
        }
        .shadow(color: Color.accentColor.opacity(0.25), radius: 20, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the hitchhiking guide")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("You're in", systemImage: "location.fill")
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Color.accentColor)
                Text(self.country.title)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            }
            Spacer(minLength: 8)
            if let flag = self.country.flag {
                Text(flag)
                    .font(.system(size: 60))
                    .rotationEffect(.degrees(8))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                    .accessibilityHidden(true)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            if self.country.placeCount > 0 {
                StatPill(text: String(localized: "\(self.country.placeCount) places", comment: "Cities and areas in a country"),
                         systemImage: "building.2.fill")
            }
            if self.country.spotCount > 0 {
                StatPill(text: String(localized: "\(self.country.spotCount) spots", comment: "Number of hitchhiking spots"),
                         systemImage: "hand.thumbsup.fill")
            }
            if let hitchability = self.country.hitchability {
                StatPill(text: hitchability, systemImage: "star.fill")
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassBackground(in: .circle)
        }
    }

    private var facts: [(label: String, value: String)] {
        var facts = [(label: String, value: String)]()
        if let capital = self.country.capital {
            facts.append((label: String(localized: "Capital", comment: "Infobox label"), value: capital))
        }
        if let language = self.country.mainLanguage {
            facts.append((label: String(localized: "Language", comment: "Infobox label"), value: language))
        }
        if let currency = self.country.shortCurrency {
            facts.append((label: String(localized: "Money", comment: "Country card: the currency"), value: currency))
        }
        return facts
    }

    private var factsPanel: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(self.facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 1)
                        .padding(.vertical, 2)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(fact.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.7))
                    // Long values (e.g. two languages) wrap onto more lines at the same size.
                    Text(fact.value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 12)
        .background(.white.opacity(0.14), in: .rect(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }
}

/// A small glass capsule with an icon and a short text, e.g. "114 places".
private struct StatPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(self.text, systemImage: self.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassBackground(in: .capsule)
    }
}

#Preview {
    CountryCard(country: CountryOverview(
        id: 1, title: "Poland", hitchField: "pl", capital: "Warsaw", language: "Polish", currency: "Złoty (PLN)",
        summary: "It is an awesome country for hitchhiking and even one of the most hitchhiker friendly countries in whole Europe.",
        placeCount: 114, spotCount: 60))
        .padding()
        .background(Theme.background)
}
