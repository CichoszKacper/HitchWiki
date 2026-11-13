//
//  MapPointCard.swift
//  HitchWiki
//
//  The selected point on the map: what it is, how far away, and buttons to read its page or get directions.
//  A wiki spot shows the guide's directions; a ride spot its rating, wait and comments and the nearest
//  place in the guide.
//

import SwiftUI
import MapKit

struct MapPointCard: View {
    let point: MapPoint
    let distance: CLLocationDistance?
    /// Directions, for hitchhiking spots.
    var spotDetails: SpotDetails?
    /// Rating, waits and comments, for ride spots.
    var rideSpotDetails: RideSpotDetails?
    /// The closest place in the guide, for ride spots.
    var rideSpotPlace: MapPoint?
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
                    Text(self.subtitle)
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
            } else if let details = self.rideSpotDetails {
                RideSpotDetailsView(details: details)
                    .id(details.spotID)   // collapse the comments again for the next spot
                    .transition(.opacity)
            } else if self.isLoadingSpotDetails {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if let pageTitle = self.pageTitle {
                    NavigationLink(value: PageRoute(title: pageTitle)) {
                        Label(self.point.kind == .page
                              ? String(localized: "Open page")
                              : String(localized: "Read about \(pageTitle)", comment: "Opens the page a hitchhiking spot is on"),
                              systemImage: "book.fill")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: self.point.coordinate))
                    item.name = self.point.title
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                } label: {
                    Label("Go", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: self.pageTitle == nil ? .infinity : nil)
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

    /// The guide page to read: the point's own page, or for a ride spot the nearest place (if there is one close by).
    private var pageTitle: String? {
        self.point.kind == .rideSpot ? self.rideSpotPlace?.title : self.point.pageTitle
    }

    /// For a ride spot "Near Kraków" once the nearest place is known.
    private var subtitle: String {
        if self.point.kind == .rideSpot, let place = self.rideSpotPlace {
            return String(localized: "Near \(place.title)", comment: "Map card subtitle: the closest city to a hitchhiking spot")
        }
        return self.point.subtitle
    }
}
