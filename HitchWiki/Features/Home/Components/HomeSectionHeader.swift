//
//  HomeSectionHeader.swift
//  HitchWiki
//
//  The title above each part of the home screen, with an optional button on the right.
//

import SwiftUI

struct HomeSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let trailing: Trailing

    init(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: self.systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentColor)
            Text(self.title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            self.trailing
        }
        .padding(.horizontal, Theme.screenPadding + 4)
    }
}

extension HomeSectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.init(title, systemImage: systemImage) {
            EmptyView()
        }
    }
}

/// Shown instead of "Near you" when the app may not use the location.
struct LocationPromptCard: View {
    let isDenied: Bool
    var onEnable: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "location.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.gradient, in: .circle)

            VStack(alignment: .leading, spacing: 6) {
                Text("See what's around you")
                    .font(.headline)
                Text("Turn on location to see the closest cities, their hitchhiking spots and a guide to the country you're in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: self.onEnable) {
                    Group {
                        if self.isDenied {
                            Text("Open Settings")
                        } else {
                            Text("Turn On Location")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.top, 6)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    VStack(spacing: 24) {
        HomeSectionHeader("Recently viewed", systemImage: "clock.fill") {
            Button("Clear") {}
        }
        LocationPromptCard(isDenied: true) {}
            .padding(.horizontal)
    }
    .frame(maxHeight: .infinity)
    .background(Theme.background)
}
