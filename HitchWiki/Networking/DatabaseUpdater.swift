//
//  DatabaseUpdater.swift
//  HitchWiki
//
//  Keeps the offline databases up to date: one guide database per language, plus the spots database
//  (the same for every language). The heavy work (downloading the Hitchwiki dump and the rides dataset and
//  parsing them) happens weekly on GitHub Actions (.github/workflows/update-database.yml), which publishes
//  a ready database plus a manifest for each (manifest.json for English, manifest-pl.json for Polish,
//  manifest-spots.json for the spots). The app only:
//    1. downloads the small manifest and compares its version with the database in use,
//    2. downloads the compressed database when it's newer (not on Low Data Mode),
//    3. unpacks and checks it (size, SHA-256, schema, opens it), then swaps it in atomically.
//  Everything runs on this actor, off the main thread.
//

import Foundation
import CryptoKit

/// Where downloaded databases live (Application Support, excluded from iCloud backup).
enum DatabaseFiles {
    static var directory: URL {
        let directory = URL.applicationSupportDirectory.appending(path: "Database", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// The downloaded database for a language. English keeps the original file name, so copies
    /// downloaded by earlier versions of the app are still found.
    static func installedURL(for language: AppLanguage) -> URL {
        self.directory.appending(path: language == .english ? "hitchwiki.sqlite" : "hitchwiki-\(language.rawValue).sqlite")
    }

    /// The downloaded spots database (the same for every guide language).
    static var spotsURL: URL {
        self.directory.appending(path: "\(SpotsDatabase.fileName).sqlite")
    }

    /// Removes half-installed downloads left behind by an interrupted update.
    static func removeLeftovers() {
        let installed = Set(AppLanguage.allCases.map { self.installedURL(for: $0).lastPathComponent } + [self.spotsURL.lastPathComponent])
        let files = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !installed.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// manifest.json published next to the database (see tools/package_database.py).
struct DatabaseManifest: Decodable, Sendable {
    struct File: Decodable, Sendable {
        let url: URL
        let compression: String
        let sha256: String
        let size: Int
        let compressedSize: Int
    }

    struct Stats: Decodable, Sendable {
        let pages: Int
        let spots: Int
    }

    let schemaVersion: Int
    let version: Int64
    let generatedAt: String
    /// Missing in manifests published before languages were added (those are English) and for the spots.
    let language: String?
    let database: File
    /// Guide databases only.
    let stats: Stats?
}

enum DatabaseUpdateError: Error {
    case badResponse(Int)
    case unsupportedCompression(String)
    case corrupted(String)
}

actor DatabaseUpdater {
    /// Published by the GitHub Action; the release tag never changes, only its files.
    private static let releaseURL = URL(string: "https://github.com/CichoszKacper/HitchWiki/releases/download/database-latest/")!

    static func manifestURL(for language: AppLanguage) -> URL {
        self.releaseURL.appending(path: language == .english ? "manifest.json" : "manifest-\(language.rawValue).json")
    }

    static let spotsManifestURL = DatabaseUpdater.releaseURL.appending(path: "manifest-spots.json")

    /// A downloaded database must have at least this many articles to be used
    /// (the Polish Hitchwiki is much smaller than the English one).
    private static func minimumArticles(for language: AppLanguage) -> Int {
        language == .english ? 1_000 : 20
    }

    /// A downloaded spots database must have at least this many spots (about 47,000 in November 2026).
    private static let minimumSpots = 10_000

    private let session: URLSession
    private let downloadSession: URLSession
    /// For downloads the user asked for (picking a guide language): allowed on Low Data Mode too.
    private let requestedDownloadSession: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false          // offline: fail fast, keep the data we have
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)

        let downloads = URLSessionConfiguration.default
        downloads.timeoutIntervalForRequest = 60
        downloads.waitsForConnectivity = false
        downloads.allowsConstrainedNetworkAccess = false     // respect Low Data Mode for the ~8 MB files
        self.downloadSession = URLSession(configuration: downloads)

        let requested = URLSessionConfiguration.default
        requested.timeoutIntervalForRequest = 60
        requested.waitsForConnectivity = false
        self.requestedDownloadSession = URLSession(configuration: requested)
    }

    // MARK: - Guide

    /// The published manifest for `language`.
    func manifest(for language: AppLanguage) async throws -> DatabaseManifest {
        try await self.manifest(at: Self.manifestURL(for: language))
    }

    /// The manifest of a newer, compatible database in `language`, or nil when the one in use is current.
    func availableUpdate(for language: AppLanguage, currentVersion: Int64) async throws -> DatabaseManifest? {
        let manifest = try await self.manifest(for: language)
        guard manifest.schemaVersion == HitchwikiDatabase.supportedSchemaVersion,
              manifest.version > currentVersion else {
            return nil
        }
        return manifest
    }

    /// Downloads, verifies and installs the `language` database described by `manifest`, and opens it.
    /// - Parameter userRequested: the user is waiting for it (allowed on Low Data Mode).
    func install(_ manifest: DatabaseManifest, language: AppLanguage, userRequested: Bool = false) async throws -> HitchwikiDatabase {
        guard manifest.schemaVersion == HitchwikiDatabase.supportedSchemaVersion else {
            throw DatabaseUpdateError.corrupted("schema \(manifest.schemaVersion) isn't supported")
        }
        let destination = DatabaseFiles.installedURL(for: language)
        try await self.downloadAndInstall(manifest, staging: "staging-\(language.rawValue)-\(manifest.version).sqlite",
                                          destination: destination, userRequested: userRequested) { staging in
            let candidate = try HitchwikiDatabase(url: staging)
            guard candidate.schemaVersion == HitchwikiDatabase.supportedSchemaVersion,
                  candidate.version == manifest.version,
                  candidate.language == language,
                  try candidate.pageCount() >= Self.minimumArticles(for: language) else {
                throw DatabaseUpdateError.corrupted("unexpected contents")
            }
        }
        return try HitchwikiDatabase(url: destination)
    }

    // MARK: - Spots

    /// The manifest of a newer, compatible spots database, or nil when the one in use is current.
    func availableSpotsUpdate(currentVersion: Int64) async throws -> DatabaseManifest? {
        let manifest = try await self.manifest(at: Self.spotsManifestURL)
        guard manifest.schemaVersion == SpotsDatabase.supportedSchemaVersion,
              manifest.version > currentVersion else {
            return nil
        }
        return manifest
    }

    /// Downloads, verifies and installs the spots database described by `manifest`, and opens it.
    func installSpots(_ manifest: DatabaseManifest) async throws -> SpotsDatabase {
        guard manifest.schemaVersion == SpotsDatabase.supportedSchemaVersion else {
            throw DatabaseUpdateError.corrupted("spots schema \(manifest.schemaVersion) isn't supported")
        }
        let destination = DatabaseFiles.spotsURL
        try await self.downloadAndInstall(manifest, staging: "staging-spots-\(manifest.version).sqlite",
                                          destination: destination, userRequested: false) { staging in
            let candidate = try SpotsDatabase(url: staging)
            guard candidate.schemaVersion == SpotsDatabase.supportedSchemaVersion,
                  candidate.version == manifest.version,
                  try candidate.countSpots() >= Self.minimumSpots else {
                throw DatabaseUpdateError.corrupted("unexpected spots contents")
            }
        }
        return try SpotsDatabase(url: destination)
    }

    // MARK: - Private

    private func manifest(at url: URL) async throws -> DatabaseManifest {
        let (data, response) = try await self.session.data(from: url)
        try Self.check(response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DatabaseManifest.self, from: data)
    }

    /// Downloads the database, checks its size and checksum, writes it to `staging` next to the installed file,
    /// runs `validate` on it, then swaps it in for `destination`.
    private func downloadAndInstall(_ manifest: DatabaseManifest, staging stagingName: String, destination: URL,
                                    userRequested: Bool, validate: (URL) throws -> Void) async throws {
        guard manifest.database.compression == "deflate" else {
            throw DatabaseUpdateError.unsupportedCompression(manifest.database.compression)
        }
        let session = userRequested ? self.requestedDownloadSession : self.downloadSession
        let (downloadedURL, response) = try await session.download(from: manifest.database.url)
        defer { try? FileManager.default.removeItem(at: downloadedURL) }
        try Self.check(response)

        // Raw DEFLATE, which is what Apple calls "zlib" here.
        let compressed = try Data(contentsOf: downloadedURL)
        let data = try (compressed as NSData).decompressed(using: .zlib) as Data
        guard data.count == manifest.database.size else {
            throw DatabaseUpdateError.corrupted("size \(data.count), expected \(manifest.database.size)")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.database.sha256 else {
            throw DatabaseUpdateError.corrupted("checksum mismatch")
        }

        // Write next to the installed file, check it opens and looks right, then swap it in.
        DatabaseFiles.removeLeftovers()
        let staging = DatabaseFiles.directory.appending(path: stagingName)
        try data.write(to: staging, options: .atomic)
        do {
            try validate(staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                // Atomic rename: a connection still reading the old file keeps working until it's released.
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true   // it can always be downloaded again
        var excluded = destination
        try? excluded.setResourceValues(values)
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DatabaseUpdateError.badResponse(http.statusCode)
        }
    }
}
