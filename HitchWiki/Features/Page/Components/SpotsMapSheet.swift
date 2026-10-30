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

    @State private var position: MapCameraPosition
    @State private var selectedSpotID: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    private static let spotSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)

    init(title: String, spots: [PageSpot], sections: [PageSection], mapFrame: MapFrame?, focus: PageSpot? = nil) {
        self.title = title
        self.spots = spots
        self.sections = sections
        if let focus {
            self._position = State(initialValue: .region(MKCoordinateRegion(center: focus.coordinate, span: Self.spotSpan)))
        } else if let mapFrame {
            self._position = State(initialValue: .region(mapFrame.region))
        } else {
            self._position = State(initialValue: .automatic)
        }
        self._selectedSpotID = State(initialValue: focus?.id)
    }

    private var selectedSpot: PageSpot? {
        self.spots.first { $0.id == self.selectedSpotID }
    }

    var body: some View {
        NavigationStack {
            Map(position: self.$position, selection: self.$selectedSpotID) {
                ForEach(self.spots) { spot in
                    Marker(spot.name, systemImage: "hand.thumbsup.fill", coordinate: spot.coordinate)
                        .tint(Color.accentColor)
                        .tag(spot.id)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapScaleView()
            }
            .safeAreaInset(edge: .bottom) {
                if let spot = self.selectedSpot {
                    SpotDetailCard(spot: spot, pageTitle: self.title,
                                   section: self.sections.first { $0.path == spot.sectionPath })
                        .id(spot.id)
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: self.selectedSpotID)
            .onChange(of: self.selectedSpotID) { _, newValue in
                guard let spot = self.spots.first(where: { $0.id == newValue }) else {
                    return
                }
                withAnimation(.smooth) {
                    self.position = .region(MKCoordinateRegion(center: spot.coordinate, span: Self.spotSpan))
                }
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
