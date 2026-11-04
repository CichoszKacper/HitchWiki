//
//  MapTabView.swift
//  HitchWiki
//
//  Every Hitchwiki page with coordinates and every hitchhiking spot on one map.
//  Points close together are grouped into bubbles (tap to zoom in); the row at the bottom
//  shows what's nearest to the user.
//
//  The map itself is HitchMapView (UIKit's MKMapView): offline, SwiftUI's Map could stop taking
//  touches in areas without cached tiles. Offline the map is flat (3D terrain needs data too) and a
//  capsule explains the missing background.
//

import SwiftUI
import MapKit

struct MapTabView: View {
    @State private var viewModel = MapViewModel()
    @State private var location = LocationManager()
    @State private var router = Router()
    @Environment(DatabaseSync.self) private var sync

    private var network: NetworkMonitor { .shared }

    var body: some View {
        NavigationStack(path: self.$router.path) {
            HitchMapView(singles: self.viewModel.singles,
                         clusters: self.viewModel.clusters,
                         selectedID: self.$viewModel.selectedID,
                         cameraMove: self.viewModel.cameraMove,
                         isOnline: self.network.isOnline,
                         onRegionChange: { region in
                             self.viewModel.regionChanged(region)
                         },
                         onClusterTap: { cluster in
                             self.viewModel.zoom(into: cluster)
                         })
            .ignoresSafeArea(.container, edges: .top)
            .onGeometryChange(for: CGSize.self) { geometry in
                geometry.size
            } action: { size in
                self.viewModel.mapSizeChanged(size)
            }
            .task {
                await self.viewModel.loadPoints()
            }
            .onChange(of: self.viewModel.selectedID) {
                self.viewModel.selectionChanged()
            }
            .safeAreaInset(edge: .bottom) {
                self.bottomPanel
                    .padding(.bottom, 8)
            }
            .overlay(alignment: .top) {
                if !self.network.isOnline {
                    Label("Offline: the map only shows areas you've looked at before", systemImage: "wifi.slash")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassBackground(in: .capsule)
                        .padding(.horizontal, 60)   // clear of the map controls
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: self.network.isOnline)
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
        .onChange(of: self.sync.revision) {
            Task {
                await self.viewModel.reload(location: self.location.location)
            }
        }
        // initial: also handle a position that is already known when the tab appears.
        .onChange(of: self.location.location, initial: true) { _, newLocation in
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
                         spotDetails: self.viewModel.selectedSpotDetails,
                         isLoadingSpotDetails: self.viewModel.isLoadingSpotDetails) {
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
        .environment(DatabaseSync())
}
