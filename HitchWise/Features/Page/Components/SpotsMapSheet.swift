//
//  SpotsMapSheet.swift
//  HitchWiki
//
//  A full map of a page's hitchhiking spots. Selecting one shows a card with directions.
//

import SwiftUI
import MapKit

struct SpotsMapSheet: View {
    let title: String
    let spots: [PageSpot]
    /// The page's sections, to show each spot's directions.
    let sections: [PageSection]

    @State private var selectedSpotID: Int?
    @State private var controller = MapController()
    private let initialRegion: GeoRegion?
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    /// Zoom when showing one spot: a few streets around it.
    private static let spotZoom = 15.0

    init(title: String, spots: [PageSpot], sections: [PageSection], mapFrame: MapFrame?, focus: PageSpot? = nil) {
        self.title = title
        self.spots = spots
        self.sections = sections
        if let focus {
            self.initialRegion = GeoRegion(center: focus.coordinate, meters: 1_500)
        } else if let mapFrame {
            self.initialRegion = mapFrame.region
        } else {
            self.initialRegion = MapFrame.fitting(spots.map(\.coordinate), minimumSpan: 0.02)?.region
        }
        self._selectedSpotID = State(initialValue: focus?.id)
    }

    private var selectedSpot: PageSpot? {
        self.spots.first { $0.id == self.selectedSpotID }
    }

    private var markers: [MapMarker] {
        let color = (UIColor(named: "AccentColor") ?? .systemOrange).hexString
        return self.spots.map {
            MapMarker(id: String($0.id), latitude: $0.latitude, longitude: $0.longitude, color: color,
                      symbol: "hand.thumbsup.fill", title: $0.name)
        }
    }

    var body: some View {
        NavigationStack {
            HitchMapView(controller: self.controller, markers: self.markers,
                         selectedID: self.selectedSpotID.map(String.init),
                         initialRegion: self.initialRegion) { id in
                withAnimation(Theme.spring) {
                    self.selectedSpotID = id.flatMap(Int.init)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                if let spot = self.selectedSpot {
                    SpotDetailCard(spot: spot, pageTitle: self.title,
                                   section: self.sections.first { $0.path == spot.sectionPath })
                        .id(spot.id)
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MapAttribution(showsSpotsCredit: false)
                    .padding(.bottom, 4)
            }
            .animation(Theme.spring, value: self.selectedSpotID)
            .onChange(of: self.selectedSpotID) { _, newValue in
                guard let spot = self.spots.first(where: { $0.id == newValue }) else {
                    return
                }
                self.controller.fly(to: spot.coordinate, zoom: Self.spotZoom)
            }
            .navigationTitle(self.title)
            .navigationBarTitleDisplayMode(.inline)
            // A link in the directions closes the map and opens the page underneath.
            .opensPageLinks(with: self.router) {
                self.dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        self.dismiss()
                    }
                }
            }
        }
    }
}

/// The selected spot: its name, the wiki's directions, and directions in Apple Maps.
struct SpotDetailCard: View {
    let spot: PageSpot
    let pageTitle: String
    /// The section the spot was written in.
    let section: PageSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.gradient, in: .circle)
                Text(self.spot.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: self.spot.coordinate))
                    item.name = self.spot.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                } label: {
                    Label("Go", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            if let section = self.section {
                SpotDetailsView(pageTitle: self.pageTitle,
                                headings: Array(self.spot.sectionPath.components(separatedBy: " > ").dropLast()),
                                text: section.text, links: section.links)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
