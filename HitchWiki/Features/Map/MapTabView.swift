//
//  MapTabView.swift
//  HitchWiki
//
//  Every Hitchwiki page with coordinates and every hitchhiking spot on one map.
//  Markers load for the visible area; the row at the bottom shows what's nearest to the user.
//

import SwiftUI
import MapKit

struct MapTabView: View {
    @State private var viewModel = MapViewModel()
    @State private var location = LocationManager()
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: self.$router.path) {
            Map(position: self.$viewModel.position, selection: self.$viewModel.selectedID) {
                UserAnnotation()
                ForEach(self.viewModel.points) { point in
                    Marker(point.title, systemImage: point.systemImage, coordinate: point.coordinate)
                        .tint(point.tint)
                        .tag(point.id)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                self.viewModel.regionChanged(context.region)
            }
            .onChange(of: self.viewModel.selectedID) {
                self.viewModel.selectionChanged()
            }
            .safeAreaInset(edge: .bottom) {
                self.bottomPanel
                    .padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PageRoute.self) { route in
                PageView(title: route.title)
            }
        }
        .environment(self.router)
        .opensPageLinks(with: self.router)
        // Use GPS only while the map is on screen.
        .onAppear {
            self.location.start()
        }
        .onDisappear {
            self.location.stop()
        }
        .onChange(of: self.location.location) { _, newLocation in
            if let newLocation {
                self.viewModel.centerOnUserIfNeeded(newLocation)
                self.viewModel.updateNearby(from: newLocation)
            }
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if let point = self.viewModel.selectedPoint {
            MapPointCard(point: point, distance: self.viewModel.distance(to: point),
                         spotDetails: self.viewModel.selectedSpotDetails) {
                self.viewModel.clearSelection()
            }
            .padding(.horizontal, Theme.screenPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if !self.viewModel.nearby.isEmpty {
            NearbyCarousel(nearby: self.viewModel.nearby) { point in
                self.viewModel.focus(on: point)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if self.location.isDenied {
            self.locationPrompt
                .padding(.horizontal, Theme.screenPadding)
                .transition(.opacity)
        }
    }

    private var locationPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(.secondary)
            Text("Turn on location to see spots near you")
                .font(.subheadline)
            Spacer(minLength: 0)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }
}

#Preview {
    MapTabView()
}
