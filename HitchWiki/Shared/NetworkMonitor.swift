//
//  NetworkMonitor.swift
//  HitchWise
//
//  Whether the phone has an internet connection right now. The guide works offline either way;
//  the map uses this to switch to a flat style and to say why its background may be missing.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        self.monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = isOnline
            }
        }
        self.monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}
