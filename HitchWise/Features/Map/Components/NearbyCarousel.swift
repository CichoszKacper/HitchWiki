//
//  NearbyCarousel.swift
//  HitchWiki
//
//  A sideways-scrolling row of the closest spots, service stations and places.
//

import SwiftUI

struct NearbyCarousel: View {
    let nearby: [NearbyPoint]
    var onSelect: (MapPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Near you", systemImage: "location.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(self.nearby) { item in
                        Button {
                            self.onSelect(item.point)
                        } label: {
                            NearbyCard(item: item)
                        }
                        .buttonStyle(.pressable)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                .opacity(phase.isIdentity ? 1 : 0.6)
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
    }
}

private struct NearbyCard: View {
    let item: NearbyPoint

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: self.item.point.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(self.item.point.tint.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.item.point.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(self.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(width: 230, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
    }

    /// "350 m", or for a ride spot "350 m · ★ 4.3".
    private var detail: String {
        let distance = self.item.distance.formattedDistance
        guard self.item.point.kind == .rideSpot, let rating = self.item.point.rating else {
            return distance
        }
        return "\(distance) · ★ \(rating.formatted(.number.precision(.fractionLength(1))))"
    }
}
