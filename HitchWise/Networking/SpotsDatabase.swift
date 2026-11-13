//
//  SpotsDatabase.swift
//  HitchWise
//
//  Read-only access to hitchspots.sqlite: ~47,000 hitchhiking spots with their rating, typical wait and
//  what riders wrote, from the Hitchhiking Rides Dataset (maps.hitchwiki.org, Hitchmap, the old Hitchwiki
//  Maps, liftershalte.info). Built by tools/build_spots.py; see tools/README.md.
//
//  Separate from the guide database because it doesn't depend on the guide language and has its own licence
//  (ODbL) and update cycle. One copy ships with the app; DatabaseSync installs newer ones.
//

import Foundation
import CoreLocation
import SQLite3

/// What one rider wrote about a spot.
struct SpotComment: Identifiable, Hashable, Sendable {
    /// Position at the spot, 0 = newest.
    let id: Int
    /// Year and month of the ride, e.g. "2024-03". Nil if unknown.
    let month: String?
    /// Nil when it was posted anonymously.
    let nickname: String?
    /// 1 (senseless) to 5 (very good).
    let rating: Int?
    let waitMinutes: Int?
    let text: String
    /// Where it was logged, e.g. "hitchmap.com".
    let source: String
    /// "odbl", "cc-by-sa-4.0", "cc-by-4.0".
    let license: String
}

/// Everything known about a spot from the rides logged there.
struct RideSpotDetails: Hashable, Sendable {
    let spotID: Int64
    let rides: Int
    /// Average, 1 (senseless) to 5 (very good).
    let rating: Double?
    /// Median of the waits people logged.
    let waitMinutes: Int?
    /// How many rides logged a wait.
    let waitCount: Int
    /// Year and month of the latest ride, e.g. "2026-10".
    let lastRide: String?
    /// Where the rides were logged, e.g. ["hitchmap.com", "hitchwiki.org"].
    let sources: [String]
    /// Licences of those rides, e.g. ["cc-by-sa-4.0", "odbl"].
    let licenses: [String]
    /// Newest first.
    let comments: [SpotComment]
}

/// Safe to use from any thread: every query runs on one serial queue.
final class SpotsDatabase: @unchecked Sendable {
    /// Tables/columns this build of the app understands. Matches SCHEMA_VERSION in tools/build_spots.py.
    static let supportedSchemaVersion = 1
    /// File name of the copy in the app bundle and of downloaded copies.
    static let fileName = "hitchspots"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: SpotsDatabase? = SpotsDatabase.openLocal()

    /// The database in use: the newer of the downloaded one and the one bundled with the app.
    static var shared: SpotsDatabase? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.current
    }

    static func replaceShared(with database: SpotsDatabase) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.current = database
    }

    /// Data version (YYYYMMDDHHMM of the build).
    let version: Int64
    let schemaVersion: Int
    /// Number of spots, as recorded when the database was built.
    let spotCount: Int

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "SpotsDatabase")

    init(url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw DatabaseError.cannotOpen(message)
        }
        // A guide database put here by mistake has no spots.
        guard Self.meta("kind", in: handle) == "spots" else {
            sqlite3_close(handle)
            throw DatabaseError.cannotOpen("not a spots database")
        }
        self.db = handle
        self.version = Self.meta("version", in: handle).flatMap { Int64($0) } ?? 0
        self.schemaVersion = Self.meta("schema_version", in: handle).flatMap { Int($0) } ?? 0
        self.spotCount = Self.meta("spots", in: handle).flatMap { Int($0) } ?? 0
    }

    deinit {
        sqlite3_close(self.db)
    }

    /// The best copy on the phone: the newer of the downloaded and the bundled database.
    static func openLocal() -> SpotsDatabase? {
        let installed = (try? SpotsDatabase(url: DatabaseFiles.spotsURL)).flatMap { database in
            database.schemaVersion == self.supportedSchemaVersion ? database : nil
        }
        let bundled = self.openBundled()
        if let installed, installed.version > (bundled?.version ?? 0) {
            return installed
        }
        return bundled ?? installed
    }

    static func openBundled() -> SpotsDatabase? {
        guard let url = Bundle.main.url(forResource: self.fileName, withExtension: "sqlite") else {
            print("hitchspots.sqlite is missing from the app bundle")
            return nil
        }
        do {
            return try SpotsDatabase(url: url)
        } catch {
            print("Could not open the bundled hitchspots.sqlite: \(error)")
            return nil
        }
    }

    /// Number of spots actually in the file; used to sanity-check a downloaded database.
    func countSpots() throws -> Int {
        try self.query("SELECT COUNT(*) FROM spots") { Int(Self.int($0, 0)) }.first ?? 0
    }

    // MARK: - Map

    /// Every spot, for clustering in memory.
    func allMapPoints() throws -> [MapPoint] {
        let title = String(localized: "Hitchhiking spot")
        return try self.query("SELECT id, lat, lng, rating, rides FROM spots") { Self.mapPoint($0, title: title) }
    }

    /// The closest spots to a location, searching up to ~0.5° away. Not sorted.
    func nearestMapPoints(latitude: Double, longitude: Double, limit: Int) throws -> [MapPoint] {
        let title = String(localized: "Hitchhiking spot")
        // A degree of longitude gets shorter away from the equator.
        let longitudeScale = max(cos(latitude * .pi / 180), 0.01)
        let sql = """
            SELECT id, lat, lng, rating, rides FROM spots
            WHERE lat BETWEEN ?1 - 0.5 AND ?1 + 0.5 AND lng BETWEEN ?2 - ?3 AND ?2 + ?3
            ORDER BY (lat - ?1) * (lat - ?1) + (lng - ?2) * (lng - ?2) * ?4
            LIMIT ?5
            """
        return try self.query(sql, [latitude, longitude, 0.5 / longitudeScale, longitudeScale * longitudeScale, limit]) {
            Self.mapPoint($0, title: title)
        }
    }

    func details(spotID: Int64) throws -> RideSpotDetails? {
        let spotSQL = "SELECT rides, rating, wait_minutes, wait_count, last_ride, sources, licenses FROM spots WHERE id = ?"
        guard let spot = try self.query(spotSQL, [spotID], map: { statement in
            (rides: Int(Self.int(statement, 0)), rating: Self.double(statement, 1), wait: Self.optionalInt(statement, 2),
             waitCount: Int(Self.int(statement, 3)), lastRide: Self.text(statement, 4),
             sources: Self.list(Self.text(statement, 5)), licenses: Self.list(Self.text(statement, 6)))
        }).first else {
            return nil
        }
        let commentSQL = """
            SELECT position, date, nickname, rating, wait_minutes, text, source, license
            FROM comments WHERE spot_id = ? ORDER BY position
            """
        let comments = try self.query(commentSQL, [spotID]) { statement in
            SpotComment(id: Int(Self.int(statement, 0)), month: Self.text(statement, 1), nickname: Self.text(statement, 2),
                        rating: Self.optionalInt(statement, 3), waitMinutes: Self.optionalInt(statement, 4),
                        text: Self.text(statement, 5) ?? "", source: Self.text(statement, 6) ?? "",
                        license: Self.text(statement, 7) ?? "")
        }
        return RideSpotDetails(spotID: spotID, rides: spot.rides, rating: spot.rating, waitMinutes: spot.wait,
                               waitCount: spot.waitCount, lastRide: spot.lastRide, sources: spot.sources,
                               licenses: spot.licenses, comments: comments)
    }

    private static func mapPoint(_ statement: OpaquePointer, title: String) -> MapPoint {
        MapPoint(kind: .rideSpot, rowID: Self.int(statement, 0), title: title, pageTitle: "", infoboxType: nil,
                 latitude: Self.double(statement, 1) ?? 0, longitude: Self.double(statement, 2) ?? 0,
                 rating: Self.double(statement, 3), rideCount: Int(Self.int(statement, 4)))
    }

    // MARK: - SQLite helpers

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func meta(_ key: String, in db: OpaquePointer?) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ?", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, Self.transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: value)
    }

    private func query<T>(_ sql: String, _ arguments: [Any] = [], map: (OpaquePointer) -> T) throws -> [T] {
        try self.queue.sync { () throws -> [T] in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK, let statement = statement else {
                throw DatabaseError.query(String(cString: sqlite3_errmsg(self.db)))
            }
            defer { sqlite3_finalize(statement) }

            for (offset, argument) in arguments.enumerated() {
                let index = Int32(offset + 1)
                switch argument {
                case let value as Int64:
                    sqlite3_bind_int64(statement, index, value)
                case let value as Int:
                    sqlite3_bind_int64(statement, index, Int64(value))
                case let value as Double:
                    sqlite3_bind_double(statement, index, value)
                case let value as String:
                    sqlite3_bind_text(statement, index, value, -1, Self.transient)
                default:
                    sqlite3_bind_null(statement, index)
                }
            }

            var rows = [T]()
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_ROW {
                    rows.append(map(statement))
                } else if step == SQLITE_DONE {
                    return rows
                } else {
                    throw DatabaseError.query(String(cString: sqlite3_errmsg(self.db)))
                }
            }
        }
    }

    private static func int(_ statement: OpaquePointer, _ column: Int32) -> Int64 {
        sqlite3_column_int64(statement, column)
    }

    private static func optionalInt(_ statement: OpaquePointer, _ column: Int32) -> Int? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
    }

    private static func double(_ statement: OpaquePointer, _ column: Int32) -> Double? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: pointer)
    }

    /// "a,b" -> ["a", "b"].
    private static func list(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",").map(String.init)
    }
}
