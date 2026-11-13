//
//  MapViewModel.swift
//  HitchWiki
//
//  Markers for the map, what's near the user, and the selected point. Points come from the guide (pages and
//  the spots written on them) and from the spots database (places where people logged rides, with ratings,
//  waits and comments). MapLibre groups them into bubbles itself (see HitchMapView).
//

import SwiftUI
import CoreLocation
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
    var selectedID: String?
    /// Every point, as drawn on the map. Built once per data load.
    private(set) var markers = [MapMarker]()
    private(set) var nearby = [NearbyPoint]()
    private(set) var selectedPoint: MapPoint?
    /// Directions for the selected point when it's a hitchhiking spot.
    private(set) var selectedSpotDetails: SpotDetails?
    /// Rating, waits and comments for the selected point when it's a ride spot.
    private(set) var selectedRideSpotDetails: RideSpotDetails?
    /// The closest city or area to the selected ride spot, to read about it.
    private(set) var selectedRideSpotPlace: MapPoint?
    private(set) var isLoadingSpotDetails = false

    /// Moves the map.
    @ObservationIgnored let controller = MapController()

    /// How much of the map the first view of the user's location covers: roughly a city and its outskirts.
    private static let cityDistance: CLLocationDistance = 25_000

    @ObservationIgnored private let injectedDatabase: HitchwikiDatabase?
    @ObservationIgnored private let injectedSpots: SpotsDatabase?
    /// Read at query time, so a database installed by DatabaseSync is used straight away.
    private var database: HitchwikiDatabase? { self.injectedDatabase ?? HitchwikiDatabase.shared }
    private var spotsDatabase: SpotsDatabase? { self.injectedSpots ?? SpotsDatabase.shared }
    @ObservationIgnored private var allPoints = [MapPoint]()
    @ObservationIgnored private var pointsByID = [String: MapPoint]()
    @ObservationIgnored private var nearbyTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
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
        let (points, markers) = await Task.detached(priority: .userInitiated) {
            let points = ((try? database?.allMapPoints()) ?? []) + ((try? spots?.allMapPoints()) ?? [])
            return (points, points.map(\.marker))
        }.value
        self.allPoints = points
        self.pointsByID = Dictionary(points.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.markers = markers
    }

    /// Recomputes the nearby list when the user has moved more than a few hundred metres.
    /// The first time the user's location arrives, flies the map to their city (not street level).
    /// Does nothing on later location updates, so the map doesn't keep snapping back to the user.
    func centerOnUserIfNeeded(_ location: CLLocation) {
        guard !self.hasCenteredOnUser else {
            return
        }
        self.hasCenteredOnUser = true
        self.controller.show(GeoRegion(center: location.coordinate, meters: Self.cityDistance))
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

    /// A marker was tapped on the map (nil: the map itself).
    func select(_ id: String?) {
        self.selectedID = id
        self.selectionChanged()
    }

    /// Keeps `selectedPoint` in step with the map's selection.
    func selectionChanged() {
        let point = self.selectedID.flatMap { self.pointsByID[$0] }
        withAnimation(Theme.spring) {
            self.selectedPoint = self.selectedID == nil ? nil : (point ?? self.selectedPoint)
        }
        self.loadDetails(for: self.selectedPoint)
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
            self.markers.append(point.marker)
        }
        self.selectedID = point.id
        self.selectionChanged()
        self.controller.fly(to: point.coordinate, zoom: 14)
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
