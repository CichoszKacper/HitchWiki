//
//  PageHeroHeader.swift
//  HitchWiki
//
//  The top of a page: a map of the place and its hitchhiking spots (or a drifting gradient when
//  there are no coordinates), with the title on top. It stretches when pulled down and the title
//  fades as it scrolls away.
//

import SwiftUI
import MapKit

struct PageHeroHeader: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let mapFrame: MapFrame?
    let spots: [PageSpot]
    var onOpenMap: (() -> Void)?

    static let height: CGFloat = 360

    var body: some View {
        let height = Self.height
        return ZStack(alignment: .bottomLeading) {
            self.backdrop
                .frame(height: Self.height)
                .frame(maxWidth: .infinity)
                .clipped()
                .visualEffect { content, proxy in
                    // Pulling down: grow from the bottom edge so the header fills the gap.
                    let pull = max(0, proxy.frame(in: .scrollView).minY)
                    return content.scaleEffect(1 + pull / height, anchor: .bottom)
                }

            LinearGradient(stops: [.init(color: .clear, location: 0.3),
                                   .init(color: Theme.background.opacity(0.85), location: 0.78),
                                   .init(color: Theme.background, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

            self.titleBlock
                .frame(height: Self.height, alignment: .bottomLeading)
                .visualEffect { content, proxy in
                    // Scrolling up: fade the title out as it moves under the navigation bar.
                    let scrolled = max(0, -proxy.frame(in: .scrollView).minY)
                    return content.opacity(1 - min(1, scrolled / 220))
                }
        }
        .frame(height: Self.height)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let mapFrame = self.mapFrame {
            Map(initialPosition: .region(mapFrame.region), interactionModes: []) {
                ForEach(self.spots) { spot in
                    Marker("", systemImage: "hand.thumbsup.fill", coordinate: spot.coordinate)
                        .tint(Color.accentColor)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
        } else {
            AnimatedMeshBackground(seed: self.title)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: self.symbol)
                        .font(.system(size: 150, weight: .bold))
                        .foregroundStyle(.white.opacity(0.22))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 30, y: 70)
                }
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let subtitle = self.subtitle {
                    Text(subtitle.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(1.4)
                        .foregroundStyle(Color.accentColor)
                }
                Text(self.title)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            if let onOpenMap = self.onOpenMap, self.mapFrame != nil {
                Button(action: onOpenMap) {
                    Label(self.spots.isEmpty ? "Map" : "\(self.spots.count)", systemImage: "map.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: .capsule)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(self.spots.isEmpty ? "Open map" : "Open map with \(self.spots.count) spots")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}
