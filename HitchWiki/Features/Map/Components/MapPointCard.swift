//
//  MapPointCard.swift
//  HitchWiki
//
//  The selected point on the map: what it is, how far away, and buttons to read its page or get directions.
//

import SwiftUI
import MapKit

struct MapPointCard: View {
    let point: MapPoint
    let distance: CLLocationDistance?
    /// Directions, for hitchhiking spots.
    var spotDetails: SpotDetails?
    var isLoadingSpotDetails = false
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: self.point.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(self.point.tint.gradient, in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.point.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(self.point.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let distance = self.distance {
                        Label(distance.formattedDistance, systemImage: "location.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 0)
                Button(action: self.onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: .circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close")
            }

            if let details = self.spotDetails {
                SpotDetailsView(pageTitle: details.pageTitle, headings: Array(details.headings.dropLast()),
                                text: details.text, links: details.links)
                    .id(details.spotID)   // collapse "Show more" again for the next spot
                    .transition(.opacity)
            } else if self.isLoadingSpotDetails {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                NavigationLink(value: PageRoute(title: self.point.pageTitle)) {
                    Label(self.point.kind == .spot ? "Read about \(self.point.pageTitle)" : "Open page", systemImage: "book.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: self.point.coordinate))
                    item.name = self.point.title
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                } label: {
                    Label("Go", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
    }
}
