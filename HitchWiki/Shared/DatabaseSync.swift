//
//  DatabaseSync.swift
//  HitchWiki
//
//  Checks for newer Hitchwiki data when the app opens or comes back to the foreground,
//  installs it in the background and tells the UI (sync banner, screens that reload).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class DatabaseSync {
    enum Phase: Equatable {
        case idle
        case checking
        case syncing
        case updated
        case failed
    }

    private(set) var phase: Phase = .idle
    /// Version of the data in use. Screens reload their lists when it changes.
    private(set) var dataVersion: Int64 = HitchwikiDatabase.shared?.version ?? 0

    /// The banner is only shown when there is something to download, not for the quick check.
    var showsBanner: Bool {
        self.phase == .syncing || self.phase == .updated || self.phase == .failed
    }

    /// Don't check again when the app comes back to the foreground within this time.
    private static let minimumInterval: TimeInterval = 30 * 60

    @ObservationIgnored private let updater = DatabaseUpdater()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastCheck: Date?

    /// Call when the app becomes active. Offline it fails quickly and keeps the current data.
    func syncIfNeeded() {
        guard self.task == nil else {
            return
        }
        if let lastCheck = self.lastCheck, Date().timeIntervalSince(lastCheck) < Self.minimumInterval {
            return
        }
        self.lastCheck = Date()
        self.task = Task {
            await self.sync()
            self.task = nil
        }
    }

    private func sync() async {
        self.phase = .checking
        let manifest: DatabaseManifest?
        do {
            manifest = try await self.updater.availableUpdate(currentVersion: self.dataVersion)
        } catch {
            // Offline or the server is unreachable: nothing to tell the user, and check again
            // as soon as the app comes back to the foreground.
            self.lastCheck = nil
            self.phase = .idle
            return
        }
        guard let manifest else {
            self.phase = .idle
            return
        }

        withAnimation(Theme.spring) {
            self.phase = .syncing
        }
        do {
            let database = try await self.updater.install(manifest)
            HitchwikiDatabase.replaceShared(with: database)
            withAnimation(Theme.spring) {
                self.dataVersion = database.version
                self.phase = .updated
            }
        } catch let error as URLError where error.networkUnavailableReason == .constrained {
            // Low Data Mode: skip quietly; lastCheck stays set, so no retry for a while.
            withAnimation(Theme.spring) {
                self.phase = .idle
            }
            return
        } catch {
            // Keep lastCheck: the next try is in 30 minutes, not on every return to the app.
            print("Database update failed: \(error)")
            withAnimation(Theme.spring) {
                self.phase = .failed
            }
        }
        try? await Task.sleep(for: .seconds(2.5))
        withAnimation(Theme.spring) {
            self.phase = .idle
        }
    }
}
