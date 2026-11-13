//
//  MapTabView.swift
//  HitchWiki
//
//  Every Hitchwiki page with coordinates and every hitchhiking spot on one map: the spots written in the guide
//  and the ~47,000 where people logged rides (coloured by rating). Points close together are grouped into
//  bubbles (tap to zoom in); the row at the bottom shows what's nearest to the user. The data's credit
//  stays visible at the bottom, above the tab bar, as its licence asks.
//

import SwiftUI

struct MapTabView: View {
    @State private var viewModel = MapViewModel()
    @State private var location = LocationManager()
    @State private var router = Router()
    @State private var isOnline = MapConnectivity.shared.isOnline
    @State private var showsOfflineMaps = false
    @Environment(DatabaseSync.self) private var sync

    var body: some View {
        NavigationStack(path: self.$router.path) {
            ZStack(alignment: .bottom) {
                HitchMapView(controller: self.viewModel.controller,
                             markers: self.viewModel.markers,
                             clustered: true,
                             selectedID: self.viewModel.selectedID,
                             initialRegion: .europe,
                             showsUserLocation: !self.location.isDenied) { id in
                    self.viewModel.select(id)
                }
                // Under the status bar, but not under the tab bar.
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 6) {
                    self.bottomPanel
                    // The data's credit, small, just above the tab bar.
                    MapAttribution()
                }
                .padding(.bottom, 4)
            }
            .overlay(alignment: .topTrailing) {
                self.mapButtons
            }
            .overlay(alignment: .top) {
                if !self.isOnline {
                    self.offlineBadge
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: self.isOnline)
            .task {
                await self.viewModel.loadPoints()
            }
            .onReceive(NotificationCenter.default.publisher(for: MapConnectivity.didChange)) { _ in
                self.isOnline = MapConnectivity.shared.isOnline
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PageRoute.self) { route in
                PageView(title: route.title)
            }
            .sheet(isPresented: self.$showsOfflineMaps) {
                NavigationStack {
                    OfflineMapsView(suggestedCoordinate: self.viewModel.controller.visibleCenter)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    self.showsOfflineMaps = false
                                }
                            }
                        }
                }
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

    /// Go to my location, and download maps.
    private var mapButtons: some View {
        VStack(spacing: 0) {
            Button {
                if !self.viewModel.controller.centerOnUser(), let location = self.location.location {
                    self.viewModel.controller.fly(to: location.coordinate, zoom: 13)
                }
            } label: {
                Image(systemName: "location.fill")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Show my location"))
            .disabled(self.location.isDenied)
            Divider()
                .frame(width: 44)
            Button {
                self.showsOfflineMaps = true
            } label: {
                Image(systemName: "arrow.down.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Offline maps"))
        }
        .font(.system(size: 17, weight: .semibold))
        .background(.regularMaterial, in: .rect(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.trailing, 12)
        .padding(.top, 8)
    }

    /// Shown while offline: the map only has what's been downloaded.
    private var offlineBadge: some View {
        Button {
            self.showsOfflineMaps = true
        } label: {
            Label(OfflineMapStore.shared.installed.isEmpty ? String(localized: "Offline · Download maps")
                                                             : String(localized: "Offline · Using downloaded maps"),
                  systemImage: "wifi.slash")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
        }
        .buttonStyle(.pressable)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if let point = self.viewModel.selectedPoint {
            MapPointCard(point: point, distance: self.viewModel.distance(to: point),
                         spotDetails: self.viewModel.selectedSpotDetails,
                         rideSpotDetails: self.viewModel.selectedRideSpotDetails,
                         rideSpotPlace: self.viewModel.selectedRideSpotPlace,
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
