//
//  MapViewModel.swift
//  HitchWiki
//
//  Clusters and markers for the visible part of the map, what's near the user, and the selected point.
//  Points come from the guide (pages and the spots written on them) and from the spots database
//  (places where people logged rides, with ratings, waits and comments).
//

import SwiftUI
import MapKit
import Observation

/// A point with its distance from the user.
struct NearbyPoint: Identifiable, Hashable {
    let point: MapPoint
    let distance: CLLocationDistance

    var id: String { self.point.id }
}

@MainActor
@Observable
final class MapViewModel {
    var position: MapCameraPosition = .userLocation(fallback: .region(MapViewModel.europe))
    var selectedID: String?
    /// Points drawn as their own marker.
    private(set) var singles = [MapPoint]()
    /// Groups of nearby points drawn as one bubble.
    private(set) var clusters = [MapCluster]()
    private(set) var nearby = [NearbyPoint]()
    private(set) var selectedPoint: MapPoint?
    /// Directions for the selected point when it's a hitchhiking spot.
    private(set) var selectedSpotDetails: SpotDetails?
    /// Rating, waits and comments for the selected point when it's a ride spot.
    private(set) var selectedRideSpotDetails: RideSpotDetails?
    /// The closest city or area to the selected ride spot, to read about it.
    private(set) var selectedRideSpotPlace: MapPoint?
    private(set) var isLoadingSpotDetails = false

    /// How much of the map the first view of the user's location covers: roughly a city and its outskirts.
    private static let cityDistance: CLLocationDistance = 25_000

    private static let europe = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 50, longitude: 12),
                                                   span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 22))

    @ObservationIgnored private let injectedDatabase: HitchwikiDatabase?
    @ObservationIgnored private let injectedSpots: SpotsDatabase?
    /// Read at query time, so a database installed by DatabaseSync is used straight away.
    private var database: HitchwikiDatabase? { self.injectedDatabase ?? HitchwikiDatabase.shared }
    private var spotsDatabase: SpotsDatabase? { self.injectedSpots ?? SpotsDatabase.shared }
    @ObservationIgnored private var allPoints = [MapPoint]()
    @ObservationIgnored private var pointsByID = [String: MapPoint]()
    @ObservationIgnored private var region: MKCoordinateRegion? = MapViewModel.europe
    @ObservationIgnored private var mapSize = CGSize(width: 390, height: 800)
    @ObservationIgnored private var nearbyTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var clusterTask: Task<Void, Never>?
    @ObservationIgnored private var nearbyOrigin: CLLocation?
    @ObservationIgnored private var hasCenteredOnUser = false

    init(database: HitchwikiDatabase? = nil, spots: SpotsDatabase? = nil) {
        self.injectedDatabase = database
        self.injectedSpots = spots
    }

    /// New data was installed: reload every point and the nearby list.
    func reload(location: CLLocation?) async {
        // Spot ids can change between builds, so drop the selection.
        self.clearSelection()
        self.allPoints = []
        await self.loadPoints()
        self.nearbyOrigin = nil
        if let location {
            self.updateNearby(from: location)
        }
    }

    /// Loads every point once; clustering then happens in memory.
    func loadPoints() async {
        guard self.allPoints.isEmpty else {
            return
        }
        let database = self.database
        let spots = self.spotsDatabase
        let points = await Task.detached(priority: .userInitiated) {
            ((try? database?.allMapPoints()) ?? []) + ((try? spots?.allMapPoints()) ?? [])
        }.value
        self.allPoints = points
        self.pointsByID = Dictionary(points.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.recluster()
    }

    /// Call when the map stops moving.
    func regionChanged(_ region: MKCoordinateRegion) {
        self.region = region
        self.recluster()
    }

    func mapSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != self.mapSize else {
            return
        }
        self.mapSize = size
        self.recluster()
    }

    /// Zooms the map in to a cluster's points.
    func zoom(into cluster: MapCluster) {
        withAnimation(.smooth(duration: 0.7)) {
            self.position = .region(cluster.region)
        }
    }

    private func recluster() {
        guard let region = self.region, !self.allPoints.isEmpty else {
            return
        }
        // ~55,000 points: group them off the main thread so the map stays smooth. Only the latest request is applied.
        let points = self.allPoints
        let mapSize = self.mapSize
        let selectedID = self.selectedID
        self.clusterTask?.cancel()
        self.clusterTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                MapClusterer.cluster(points, in: region, mapSize: mapSize, keepingSeparate: selectedID)
            }.value
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.snappy) {
                self.singles = result.singles
                self.clusters = result.clusters
            }
        }
    }

    /// Recomputes the nearby list when the user has moved more than a few hundred metres.
    /// The first time the user's location arrives, flies the map to their city (not street level).
    /// Does nothing on later location updates, so the map doesn't keep snapping back to the user.
    func centerOnUserIfNeeded(_ location: CLLocation) {
        // No check for `position.positionedByUser`: MapKit can report the start position as moved
        // by the user before anyone touched the map, which silently skipped this zoom.
        guard !self.hasCenteredOnUser else {
            return
        }
        self.hasCenteredOnUser = true
        withAnimation(.smooth(duration: 1.2)) {
            self.position = .region(MKCoordinateRegion(center: location.coordinate,
                                                       latitudinalMeters: Self.cityDistance,
                                                       longitudinalMeters: Self.cityDistance))
        }
    }

    func updateNearby(from location: CLLocation) {
        if let origin = self.nearbyOrigin, origin.distance(from: location) < 300 {
            return
        }
        self.nearbyOrigin = location
        let database = self.database
        let spots = self.spotsDatabase
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        self.nearbyTask?.cancel()
        self.nearbyTask = Task {
            let points = await Task.detached(priority: .utility) {
                ((try? database?.nearestMapPoints(latitude: latitude, longitude: longitude, limit: 25)) ?? [])
                    + ((try? spots?.nearestMapPoints(latitude: latitude, longitude: longitude, limit: 25)) ?? [])
            }.value
            // Guide places and spots mixed, nearest first.
            let nearby = points
                .map { NearbyPoint(point: $0, distance: location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
                .sorted { $0.distance < $1.distance }
                .prefix(25)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(Theme.spring) {
                self.nearby = Array(nearby)
            }
        }
    }

    /// Keeps `selectedPoint` in step with the map's selection.
    func selectionChanged() {
        let point = self.selectedID.flatMap { self.pointsByID[$0] }
        withAnimation(Theme.spring) {
            self.selectedPoint = self.selectedID == nil ? nil : (point ?? self.selectedPoint)
        }
        self.loadDetails(for: self.selectedPoint)
        // The selected point always gets its own marker, even where it would be clustered.
        self.recluster()
    }

    private func loadDetails(for point: MapPoint?) {
        if let point, point.kind == .rideSpot {
            self.loadRideSpotDetails(for: point)
            return
        }
        self.selectedRideSpotDetails = nil
        self.selectedRideSpotPlace = nil
        guard let point, point.kind == .spot else {
            self.detailsTask?.cancel()
            self.selectedSpotDetails = nil
            self.isLoadingSpotDetails = false
            return
        }
        guard self.selectedSpotDetails?.spotID != point.rowID else {
            return
        }
        self.detailsTask?.cancel()
        self.selectedSpotDetails = nil
        self.isLoadingSpotDetails = true
        let database = self.database
        let rowID = point.rowID
        self.detailsTask = Task {
            let details = await Task.detached(priority: .userInitiated) {
                try? database?.spotDetails(rowID: rowID)
            }.value
            guard !Task.isCancelled else {
                return
            }
            withAnimation(Theme.spring) {
                self.selectedSpotDetails = details
                self.isLoadingSpotDetails = false
            }
        }
    }

    /// Rating, waits and comments of a ride spot, and the nearest city or area in the guide.
    private func loadRideSpotDetails(for point: MapPoint) {
        self.selectedSpotDetails = nil
        guard self.selectedRideSpotDetails?.spotID != point.rowID else {
            return
        }
        self.detailsTask?.cancel()
        self.selectedRideSpotDetails = nil
        self.selectedRideSpotPlace = nil
        self.isLoadingSpotDetails = true
        let database = self.database
        let spots = self.spotsDatabase
        let spotID = point.rowID
        let latitude = point.latitude
        let longitude = point.longitude
        self.detailsTask = Task {
            let (details, place) = await Task.detached(priority: .userInitiated) {
                let details = try? spots?.details(spotID: spotID)
                // Within ~50 km; farther away the guide has nothing about the spot's surroundings.
                let place = (try? database?.nearestPlaces(latitude: latitude, longitude: longitude, limit: 1))?.first
                    .flatMap { place in
                        CLLocation(latitude: latitude, longitude: longitude)
                            .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) < 50_000 ? place : nil
                    }
                return (details, place)
            }.value
            guard !Task.isCancelled else {
                return
            }
            withAnimation(Theme.spring) {
                self.selectedRideSpotDetails = details
                self.selectedRideSpotPlace = place
                self.isLoadingSpotDetails = false
            }
        }
    }

    /// Selects a point from a list and flies the map to it.
    func focus(on point: MapPoint) {
        if self.pointsByID[point.id] == nil {
            self.allPoints.append(point)
            self.pointsByID[point.id] = point
        }
        self.selectedID = point.id
        self.selectionChanged()
        withAnimation(.smooth(duration: 0.8)) {
            self.position = .region(MKCoordinateRegion(center: point.coordinate,
                                                       span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))
        }
    }

    func clearSelection() {
        self.selectedID = nil
        self.selectionChanged()
    }

    /// Distance from the user to a point, if we know where the user is.
    func distance(to point: MapPoint) -> CLLocationDistance? {
        if let nearby = self.nearby.first(where: { $0.id == point.id }) {
            return nearby.distance
        }
        return self.nearbyOrigin?.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
    }
}

extension CLLocationDistance {
    /// "350 m", "12 km" in the user's units.
    var formattedDistance: String {
        Measurement(value: self, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
