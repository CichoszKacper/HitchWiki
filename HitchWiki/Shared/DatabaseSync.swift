//
//  DatabaseSync.swift
//  HitchWise
//
//  Keeps the guide data current and in the language the user picked:
//   • checks for newer data when the app opens or comes back to the foreground and installs it
//     in the background (banner at the top while it downloads);
//   • switches the guide language: uses a copy already on the phone straight away, otherwise
//     downloads it while the user waits (first launch, Settings).
//  Screens reload their lists when `revision` changes.
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
    /// Version of the data in use.
    private(set) var dataVersion: Int64 = HitchwikiDatabase.shared?.version ?? 0
    /// Language of the data in use.
    private(set) var dataLanguage: AppLanguage = HitchwikiDatabase.shared?.language ?? .english
    /// Goes up every time another database is swapped in; screens reload when it changes.
    private(set) var revision = 0
    /// The language being downloaded at the user's request, if any.
    private(set) var downloadingLanguage: AppLanguage?

    /// The banner is only shown when there is something to download, not for the quick check.
    var showsBanner: Bool {
        self.phase == .syncing || self.phase == .updated || self.phase == .failed
    }

    /// Don't check again when the app comes back to the foreground within this time.
    private static let minimumInterval: TimeInterval = 30 * 60

    @ObservationIgnored private let updater = DatabaseUpdater()
    @ObservationIgnored private let languages: LanguageManager
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastCheck: Date?

    init(languages: LanguageManager = .shared) {
        self.languages = languages
    }

    /// Call when the app becomes active. Offline it fails quickly and keeps the current data.
    /// Waits until the guide language has been chosen on first launch.
    func syncIfNeeded() {
        guard self.task == nil, self.downloadingLanguage == nil, let language = self.languages.guideLanguage else {
            return
        }
        if let lastCheck = self.lastCheck, Date().timeIntervalSince(lastCheck) < Self.minimumInterval {
            return
        }
        self.lastCheck = Date()
        self.task = Task {
            await self.backgroundSync(language: language)
            self.task = nil
        }
    }

    /// Makes `language` the guide language. A copy on the phone is used at once; otherwise it is
    /// downloaded first. Returns false if that download failed: the language and the data then stay as they were.
    @discardableResult
    func switchGuide(to language: AppLanguage) async -> Bool {
        // Let a background update finish first, so the two don't install at the same time.
        await self.task?.value

        if self.dataLanguage == language && HitchwikiDatabase.shared != nil {
            self.languages.setGuideLanguage(language)
        } else if let local = await Self.openLocal(for: language) {
            self.use(local)
            self.languages.setGuideLanguage(language)
        } else {
            self.downloadingLanguage = language
            defer { self.downloadingLanguage = nil }
            do {
                let manifest = try await self.updater.manifest(for: language)
                let database = try await self.updater.install(manifest, language: language, userRequested: true)
                self.use(database)
                self.languages.setGuideLanguage(language)
            } catch {
                print("Couldn't download the \(language.rawValue) guide: \(error)")
                return false
            }
        }
        // Look for newer data in the new language soon.
        self.lastCheck = nil
        self.syncIfNeeded()
        return true
    }

    /// The published size and article count of the `language` guide, for the language picker. Nil offline.
    func manifest(for language: AppLanguage) async -> DatabaseManifest? {
        try? await self.updater.manifest(for: language)
    }

    // MARK: - Private

    private func use(_ database: HitchwikiDatabase) {
        HitchwikiDatabase.replaceShared(with: database)
        withAnimation(Theme.spring) {
            self.dataVersion = database.version
            self.dataLanguage = database.language
            self.revision += 1
        }
    }

    private nonisolated static func openLocal(for language: AppLanguage) async -> HitchwikiDatabase? {
        HitchwikiDatabase.openLocal(for: language)
    }

    private func backgroundSync(language: AppLanguage) async {
        self.phase = .checking
        // Data in another language (the chosen one couldn't be downloaded before): any version is newer.
        let currentVersion = self.dataLanguage == language ? self.dataVersion : 0
        let manifest: DatabaseManifest?
        do {
            manifest = try await self.updater.availableUpdate(for: language, currentVersion: currentVersion)
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
            let database = try await self.updater.install(manifest, language: language)
            // The user may have switched language while this was downloading.
            if self.languages.guideLanguage == language {
                self.use(database)
            }
            withAnimation(Theme.spring) {
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
