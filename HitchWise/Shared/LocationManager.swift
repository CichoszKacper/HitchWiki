//
//  LocationManager.swift
//  HitchWiki
//
//  The user's position, for "nearby" lists. Asks for When In Use permission the first time start() is called.
//

import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()
    /// Only track the user while a screen that needs it has called start().
    @ObservationIgnored private var wantsUpdates = false

    override init() {
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.manager.distanceFilter = 100
        self.authorizationStatus = self.manager.authorizationStatus
    }

    var isAuthorized: Bool {
        self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        self.authorizationStatus == .denied || self.authorizationStatus == .restricted
    }

    func start() {
        self.wantsUpdates = true
        if self.authorizationStatus == .notDetermined {
            self.manager.requestWhenInUseAuthorization()
        } else if self.isAuthorized {
            self.useRecentCachedLocation()
            self.manager.startUpdatingLocation()
        }
    }

    /// The system's last known position, if it is recent and accurate enough to use right away
    /// (a fresh GPS fix can take a few seconds).
    private func useRecentCachedLocation() {
        guard self.location == nil, let cached = self.manager.location,
              cached.timestamp.timeIntervalSinceNow > -600,
              cached.horizontalAccuracy >= 0, cached.horizontalAccuracy < 1_000 else {
            return
        }
        self.location = cached
    }

    func stop() {
        self.wantsUpdates = false
        self.manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isAuthorized && self.wantsUpdates {
                self.useRecentCachedLocation()
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }
        Task { @MainActor in
            self.location = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
}
