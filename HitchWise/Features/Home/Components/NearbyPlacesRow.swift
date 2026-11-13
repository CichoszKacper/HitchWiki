//
//  NearbyPlacesRow.swift
//  HitchWiki
//
//  "Near you": the closest cities as cards with a small map, the distance, the region
//  and how many hitchhiking spots their page has. Scrolls sideways.
//

import SwiftUI
import MapLibre
import UIKit

struct NearbyPlacesRow: View {
    let places: [NearbyPlace]
    /// The home screen's namespace, so a card zooms into its page.
    let transition: Namespace.ID

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(self.places) { place in
                    let sourceID = "nearby-\(place.page.title)"
                    NavigationLink(value: PageRoute(title: place.page.title, sourceID: sourceID)) {
                        NearbyPlaceCard(place: place)
                    }
                    .buttonStyle(.pressable)
                    .matchedTransitionSource(id: sourceID, in: self.transition) { source in
                        source.clipShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
                    }
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

struct NearbyPlaceCard: View {
    let place: NearbyPlace

    static let size = CGSize(width: 210, height: 238)
    private static let mapHeight: CGFloat = 126

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaceMapThumbnail(coordinate: self.place.coordinate, seed: self.place.page.title)
                .frame(height: Self.mapHeight)
                .overlay(alignment: .topLeading) {
                    Label(self.place.distance.formattedDistance, systemImage: "location.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassBackground(in: .capsule)
                        .padding(10)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(self.place.page.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detail = self.place.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                self.badge
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.cardBackground)
        .clipShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        let spots = self.place.summary?.spotCount ?? 0
        if spots > 0 {
            Label(String(localized: "\(spots) spots", comment: "Number of hitchhiking spots"), systemImage: "hand.thumbsup.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12), in: .capsule)
        } else {
            Label("Read the guide", systemImage: "book.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06), in: .capsule)
        }
    }
}

/// Grey cards that shimmer while the location and the nearby places are on their way.
struct NearbyPlacesPlaceholder: View {
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(height: 126)
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                                .frame(width: 130, height: 16)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                                .frame(width: 90, height: 12)
                        }
                        .padding(14)
                        Spacer(minLength: 0)
                    }
                    .frame(width: NearbyPlaceCard.size.width, height: NearbyPlaceCard.size.height)
                    .background(Theme.cardBackground)
                    .clipShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .shimmering()
                }
            }
        }
        .contentMargins(.horizontal, Theme.screenPadding, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
        .accessibilityLabel("Looking for places near you")
    }
}

/// A still map of the area around a place, with a pin in the middle. Drawn from a downloaded country map or
/// from OpenFreeMap; until one arrives (or offline without a download) the place's gradient is shown instead.
struct PlaceMapThumbnail: View {
    let coordinate: CLLocationCoordinate2D
    let seed: String

    @State private var snapshot: UIImage?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    /// Snapshots already taken, so scrolling back and forth doesn't fetch them again.
    @MainActor private static var cache = [String: UIImage]()

    var body: some View {
        GeometryReader { geometry in
            let key = self.cacheKey(for: geometry.size)
            ZStack {
                AnimatedMeshBackground(seed: self.seed, isAnimated: false)
                if let snapshot = self.snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(alignment: .bottomTrailing) {
                            Text(verbatim: "© OpenStreetMap")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.ultraThinMaterial, in: .capsule)
                                .padding(4)
                        }
                        .transition(.opacity)
                }
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: key) {
                await self.loadSnapshot(size: geometry.size, key: key)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func cacheKey(for size: CGSize) -> String {
        "\(self.coordinate.latitude),\(self.coordinate.longitude)|\(Int(size.width))x\(Int(size.height))|\(self.colorScheme == .dark ? "dark" : "light")"
    }

    private func loadSnapshot(size: CGSize, key: String) async {
        if let cached = Self.cache[key] {
            self.snapshot = cached
            return
        }
        self.snapshot = nil
        guard size.width > 0, size.height > 0 else {
            return
        }
        let region = GeoRegion(center: self.coordinate, meters: 12_000)
        let dark = self.colorScheme == .dark
        let options = MLNMapSnapshotOptions(styleURL: MapConnectivity.shared.styleURL(dark: dark),
                                            camera: MLNMapCamera(), size: size)
        options.coordinateBounds = region.bounds
        options.scale = self.displayScale
        options.showsLogo = false
        // A short credit is drawn by the view instead: the full one doesn't fit a card.
        options.showsAttribution = false
        guard let image = await Self.snapshot(options) else {
            // Offline or cancelled: keep the gradient.
            return
        }
        Self.cache[key] = image
        withAnimation(.easeOut(duration: 0.35)) {
            self.snapshot = image
        }
    }

    /// Snapshotters must stay alive until they finish.
    @MainActor private static var running = Set<MLNMapSnapshotter>()

    @MainActor
    private static func snapshot(_ options: MLNMapSnapshotOptions) async -> UIImage? {
        let snapshotter = MLNMapSnapshotter(options: options)
        self.running.insert(snapshotter)
        defer { self.running.remove(snapshotter) }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                snapshotter.start { snapshot, _ in
                    continuation.resume(returning: snapshot?.image)
                }
            }
        } onCancel: {
            Task { @MainActor in
                snapshotter.cancel()
            }
        }
    }
}

#Preview {
    @Previewable @Namespace var transition
    NearbyPlacesRow(places: [
        NearbyPlace(page: PageSummary(id: 1, title: "Kraków"), coordinate: CLLocationCoordinate2D(latitude: 50.054, longitude: 19.955),
                    distance: 3_200, summary: PlaceSummary(id: 1, infoboxType: "location", country: "Poland",
                                                           region: "Lesser Poland", spotCount: 5)),
        NearbyPlace(page: PageSummary(id: 2, title: "Wieliczka"), coordinate: CLLocationCoordinate2D(latitude: 49.987, longitude: 20.064),
                    distance: 14_000, summary: nil)
    ], transition: transition)
    .padding(.vertical)
    .background(Theme.background)
    .environment(Router())
}
