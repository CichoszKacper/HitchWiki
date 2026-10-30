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

    @State private var position: MapCameraPosition
    @State private var selectedSpotID: Int?
    @Environment(\.dismiss) private var dismiss

    private static let spotSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)

    init(title: String, spots: [PageSpot], mapFrame: MapFrame?, focus: PageSpot? = nil) {
        self.title = title
        self.spots = spots
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
                    SpotDetailCard(spot: spot)
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

/// The selected spot: where it is written on the page, and directions in Apple Maps.
struct SpotDetailCard: View {
    let spot: PageSpot

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.thumbsup.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.spot.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(String(format: "%.5f, %.5f", self.spot.latitude, self.spot.longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
