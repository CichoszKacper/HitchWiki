//
//  MapViewModel.swift
//  HitchWiki
//
//  Which points to show for the visible part of the map, what's near the user, and the selected point.
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
    /// Most markers drawn at once; SwiftUI's Map gets sluggish beyond a few hundred.
    static let markerLimit = 350

    /// Starts on an overview of Europe; centerOnUserIfNeeded(_:) flies to the user's city once we know where they are.
    var position: MapCameraPosition = .region(MapViewModel.europe)
    var selectedID: String?
    private(set) var points = [MapPoint]()
    private(set) var nearby = [NearbyPoint]()
    private(set) var selectedPoint: MapPoint?
    /// Directions for the selected point when it's a hitchhiking spot.
    private(set) var selectedSpotDetails: SpotDetails?

    /// How much of the map the first view of the user's location covers: roughly a city and its outskirts.
    private static let cityDistance: CLLocationDistance = 25_000

    private static let europe = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 50, longitude: 12),
                                                   span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 22))

    @ObservationIgnored private let database: HitchwikiDatabase?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var nearbyTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var nearbyOrigin: CLLocation?
    @ObservationIgnored private var hasCenteredOnUser = false

    init(database: HitchwikiDatabase? = HitchwikiDatabase.shared) {
        self.database = database
    }

    /// Call when the map stops moving: loads the points inside the visible region.
    func regionChanged(_ region: MKCoordinateRegion) {
        self.loadTask?.cancel()
        let database = self.database
        // A bit of margin so markers don't pop in right at the edge.
        let latitudeDelta = region.span.latitudeDelta * 0.6
        let longitudeDelta = region.span.longitudeDelta * 0.6
        let minLatitude = region.center.latitude - latitudeDelta
        let maxLatitude = region.center.latitude + latitudeDelta
        // Crossing the date line: just search all longitudes.
        let crossesDateLine = region.center.longitude - longitudeDelta < -180 || region.center.longitude + longitudeDelta > 180
        let minLongitude = crossesDateLine ? -180 : region.center.longitude - longitudeDelta
        let maxLongitude = crossesDateLine ? 180 : region.center.longitude + longitudeDelta

        let limit = Self.markerLimit
        self.loadTask = Task {
            let points = await Task.detached(priority: .userInitiated) {
                (try? database?.mapPoints(minLatitude: minLatitude, maxLatitude: maxLatitude,
                                          minLongitude: minLongitude, maxLongitude: maxLongitude,
                                          limit: limit)) ?? []
            }.value
            guard !Task.isCancelled else {
                return
            }
            self.points = points
        }
    }

    /// Recomputes the nearby list when the user has moved more than a few hundred metres.
    /// The first time the user's location arrives, flies the map to their city (not street level).
    /// Does nothing later on, or if the user has already moved the map themselves.
    func centerOnUserIfNeeded(_ location: CLLocation) {
        guard !self.hasCenteredOnUser else {
            return
        }
        self.hasCenteredOnUser = true
        guard !self.position.positionedByUser else {
            return
        }
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
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        self.nearbyTask?.cancel()
        self.nearbyTask = Task {
            let points = await Task.detached(priority: .utility) {
                (try? database?.nearestMapPoints(latitude: latitude, longitude: longitude, limit: 25)) ?? []
            }.value
            let nearby = points
                .map { NearbyPoint(point: $0, distance: location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
                .sorted { $0.distance < $1.distance }
            guard !Task.isCancelled else {
                return
            }
            withAnimation(Theme.spring) {
                self.nearby = nearby
            }
        }
    }

    /// Keeps `selectedPoint` in step with the map's selection.
    func selectionChanged() {
        let point = self.points.first { $0.id == self.selectedID }
            ?? self.nearby.first { $0.id == self.selectedID }?.point
        withAnimation(Theme.spring) {
            self.selectedPoint = self.selectedID == nil ? nil : (point ?? self.selectedPoint)
        }
        self.loadDetails(for: self.selectedPoint)
    }

    private func loadDetails(for point: MapPoint?) {
        guard let point, point.kind == .spot else {
            self.detailsTask?.cancel()
            self.selectedSpotDetails = nil
            return
        }
        guard self.selectedSpotDetails?.spotID != point.rowID else {
            return
        }
        self.detailsTask?.cancel()
        self.selectedSpotDetails = nil
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
            }
        }
    }

    /// Selects a point from a list and flies the map to it.
    func focus(on point: MapPoint) {
        if !self.points.contains(where: { $0.id == point.id }) {
            self.points.append(point)
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
