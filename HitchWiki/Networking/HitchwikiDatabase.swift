//
//  HitchwikiDatabase.swift
//  HitchWiki
//
//  Read-only access to hitchwiki.sqlite, the database built from the Hitchwiki XML dump
//  by tools/extract.py (see tools/README.md). Uses the SQLite that ships with iOS.
//

import Foundation
import CoreLocation
import SQLite3

/// A row in the list of pages.
struct PageSummary: Identifiable, Hashable, Sendable {
    let id: Int64
    let title: String
}

/// A link inside a heading or a section's text.
struct PageLink: Hashable, Sendable {
    enum Destination: Hashable, Sendable {
        /// Another Hitchwiki article, by title (redirects already followed).
        case page(String)
        case url(URL)
    }

    /// Position in `PageSection.title` or `PageSection.text`, in UTF-16 units like NSString.
    let range: NSRange
    let destination: Destination
}

/// A heading and the plain text below it. Level 0 is the text before the first heading.
struct PageSection: Identifiable, Hashable, Sendable {
    /// Position of the section on the page.
    let id: Int
    let level: Int
    let title: String
    /// Headings above and including this one, e.g. "Hitchhiking out > West towards Berlin > Option 1".
    let path: String
    let text: String
    var titleLinks: [PageLink] = []
    var links: [PageLink] = []
}

/// A hitchhiking spot from a {{Coords}} on the page, with the section it was written in.
struct PageSpot: Identifiable, Hashable, Sendable {
    let id: Int
    /// Matches `PageSection.path`.
    let sectionPath: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: self.latitude, longitude: self.longitude)
    }
}

/// One infobox row, e.g. capital = Warsaw.
struct InfoboxField: Hashable, Sendable {
    let name: String
    let value: String
    /// Pages linked from the value, as written on the wiki (not yet resolved).
    let links: [String]
}

/// Everything the page screen shows.
struct PageRecord: Hashable, Sendable {
    let id: Int64
    let title: String
    /// "country", "location", "polish location"... (whatever follows "Infobox" in the template name)
    let infoboxType: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    /// Infobox rows in the order they are written on the wiki.
    let infoboxFields: [InfoboxField]
    let sections: [PageSection]
    let spots: [PageSpot]

    /// Infobox values by field name, e.g. "country", "capital", "pop".
    var infobox: [String: String] {
        Dictionary(self.infoboxFields.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = self.latitude, let longitude = self.longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Something with coordinates to show on the map: a page (city, service station, country...) or a hitchhiking spot.
struct MapPoint: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case page
        case spot
    }

    let kind: Kind
    /// Page id or spot row id.
    let rowID: Int64
    /// Page title, or for a spot the heading it was written under.
    let title: String
    /// The page this point belongs to (the page itself, or the page the spot is on).
    let pageTitle: String
    let infoboxType: String?
    let latitude: Double
    let longitude: Double

    var id: String { "\(self.kind.rawValue)-\(self.rowID)" }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: self.latitude, longitude: self.longitude)
    }
}

/// What the wiki says about one hitchhiking spot: the text of the section it was written in.
struct SpotDetails: Hashable, Sendable {
    let spotID: Int64
    let pageTitle: String
    /// Headings from the top of the page down to the spot, e.g.
    /// ["Hitchhiking out", "West towards Łódź, Poznań", "Option 1, S8 onramp"].
    let headings: [String]
    /// How to get there and hitch from there.
    let text: String
    let links: [PageLink]
}

enum DatabaseError: Error {
    case missingFile
    case cannotOpen(String)
    case query(String)
}

/// Safe to use from any thread: every query runs on one serial queue.
final class HitchwikiDatabase: @unchecked Sendable {
    /// Tables/columns this build of the app understands. Matches SCHEMA_VERSION in tools/extract.py;
    /// downloaded databases with a different schema are ignored until the app is updated.
    static let supportedSchemaVersion = 1

    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: HitchwikiDatabase? = HitchwikiDatabase.openInitial()

    /// The database in use: the newest downloaded one, or the one bundled with the app.
    /// DatabaseSync swaps it when an update has been installed; view models read it at query time.
    static var shared: HitchwikiDatabase? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.current
    }

    static func replaceShared(with database: HitchwikiDatabase) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.current = database
    }

    /// Data version (YYYYMMDDHHMM of the build), 0 for databases without version info.
    let version: Int64
    let schemaVersion: Int

    private var db: OpaquePointer?
    /// SQLite runs queries one at a time on a connection.
    private let queue = DispatchQueue(label: "HitchwikiDatabase")

    init(url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw DatabaseError.cannotOpen(message)
        }
        self.db = handle
        self.version = Self.meta("version", in: handle).flatMap { Int64($0) } ?? 0
        self.schemaVersion = Self.meta("schema_version", in: handle).flatMap { Int($0) } ?? 0
    }

    convenience init(name: String, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: name, withExtension: "sqlite") else {
            throw DatabaseError.missingFile
        }
        try self.init(url: url)
    }

    deinit {
        sqlite3_close(self.db)
    }

    /// The downloaded database if there is a usable one that is newer than the bundled copy, else the bundled one.
    private static func openInitial() -> HitchwikiDatabase? {
        let bundled: HitchwikiDatabase?
        do {
            bundled = try HitchwikiDatabase(name: "hitchwiki")
        } catch {
            print("Could not open the bundled hitchwiki.sqlite: \(error)")
            bundled = nil
        }
        if let installed = try? HitchwikiDatabase(url: DatabaseFiles.installedURL),
           installed.schemaVersion == self.supportedSchemaVersion,
           installed.version > (bundled?.version ?? 0) {
            return installed
        }
        return bundled
    }

    /// Number of articles; used to sanity-check a downloaded database before switching to it.
    func pageCount() throws -> Int {
        try self.query("SELECT COUNT(*) FROM pages") { Int(Self.int($0, 0)) }.first ?? 0
    }

    private static func meta(_ key: String, in db: OpaquePointer?) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ?", -1, &statement, nil) == SQLITE_OK else {
            return nil   // older databases have no meta table
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, Self.transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: value)
    }

    // MARK: - Pages

    func allPages() throws -> [PageSummary] {
        try self.query("SELECT id, title FROM pages ORDER BY title COLLATE NOCASE") {
            PageSummary(id: Self.int($0, 0), title: Self.text($0, 1) ?? "")
        }
    }

    /// Pages whose title starts with `prefix`, ignoring case.
    func pages(titleStartingWith prefix: String) throws -> [PageSummary] {
        let escaped = prefix
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try self.query("SELECT id, title FROM pages WHERE title LIKE ? ESCAPE '\\' ORDER BY title COLLATE NOCASE",
                              [escaped + "%"]) {
            PageSummary(id: Self.int($0, 0), title: Self.text($0, 1) ?? "")
        }
    }

    /// The title of the article called `title`, following redirects ("Warszawa" -> "Warsaw"). Nil if there is none.
    func resolveTitle(_ title: String) throws -> String? {
        let sql = """
            SELECT title FROM pages WHERE title = ?1 COLLATE NOCASE
            UNION ALL
            SELECT target FROM redirects WHERE title = ?1 COLLATE NOCASE
            LIMIT 1
            """
        return try self.query(sql, [title]) { Self.text($0, 0) }.first ?? nil
    }

    func page(titled title: String) throws -> PageRecord? {
        guard let resolved = try self.resolveTitle(title) else {
            return nil
        }
        let pageSQL = "SELECT id, title, infobox_type, country, lat, lng FROM pages WHERE title = ? COLLATE NOCASE"
        guard let row = try self.query(pageSQL, [resolved], map: { statement in
            (id: Self.int(statement, 0), title: Self.text(statement, 1) ?? "", type: Self.text(statement, 2),
             country: Self.text(statement, 3), latitude: Self.double(statement, 4), longitude: Self.double(statement, 5))
        }).first else {
            return nil
        }

        let fields = try self.query("SELECT name, value, links FROM infobox_fields WHERE page_id = ? ORDER BY rowid", [row.id]) {
            InfoboxField(name: Self.text($0, 0) ?? "", value: Self.text($0, 1) ?? "", links: Self.stringArray(Self.text($0, 2)))
        }

        var sections = try self.query("SELECT idx, level, title, path, text FROM sections WHERE page_id = ? ORDER BY idx", [row.id]) {
            PageSection(id: Int(Self.int($0, 0)), level: Int(Self.int($0, 1)), title: Self.text($0, 2) ?? "",
                        path: Self.text($0, 3) ?? "", text: Self.text($0, 4) ?? "")
        }
        let indexByID = Dictionary(sections.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })

        let linkSQL = "SELECT section_idx, in_heading, start, length, target, url FROM section_links WHERE page_id = ? ORDER BY section_idx, start"
        let links = try self.query(linkSQL, [row.id]) { statement -> (section: Int, inHeading: Bool, link: PageLink)? in
            let range = NSRange(location: Int(Self.int(statement, 2)), length: Int(Self.int(statement, 3)))
            let destination: PageLink.Destination
            if let target = Self.text(statement, 4) {
                destination = .page(target)
            } else if let address = Self.text(statement, 5), let url = URL(string: address) {
                destination = .url(url)
            } else {
                return nil
            }
            return (Int(Self.int(statement, 0)), Self.int(statement, 1) != 0, PageLink(range: range, destination: destination))
        }
        for case let (sectionID, inHeading, link)? in links {
            guard let index = indexByID[sectionID] else {
                continue
            }
            if inHeading {
                sections[index].titleLinks.append(link)
            } else {
                sections[index].links.append(link)
            }
        }

        let spots = try self.query("SELECT rowid, section, lat, lng FROM spots WHERE page_id = ? ORDER BY rowid", [row.id]) {
            PageSpot(id: Int(Self.int($0, 0)), sectionPath: Self.text($0, 1) ?? "",
                     latitude: Self.double($0, 2) ?? 0, longitude: Self.double($0, 3) ?? 0)
        }

        return PageRecord(id: row.id, title: row.title, infoboxType: row.type, country: row.country,
                          latitude: row.latitude, longitude: row.longitude,
                          infoboxFields: fields, sections: sections, spots: spots)
    }

    // MARK: - Map

    /// Pages with coordinates plus spots, ranked so zooming out keeps the most useful ones:
    /// countries, then places, then service stations, then spots.
    private static let mapPointsSQL = """
        SELECT 'page' AS kind, id AS row_id, title, title AS page_title, infobox_type AS type, lat, lng,
               CASE WHEN infobox_type = 'country' THEN 0 WHEN infobox_type = 'servicestation' THEN 2 ELSE 1 END AS priority
        FROM pages WHERE lat IS NOT NULL AND lng IS NOT NULL
        UNION ALL
        SELECT 'spot', s.rowid, s.section, p.title, NULL, s.lat, s.lng, 3
        FROM spots s JOIN pages p ON p.id = s.page_id
        WHERE s.lat IS NOT NULL AND s.lng IS NOT NULL
        """

    /// Every page with coordinates and every spot (~6,500 points), for clustering in memory.
    func allMapPoints() throws -> [MapPoint] {
        try self.query("SELECT kind, row_id, title, page_title, type, lat, lng FROM (\(Self.mapPointsSQL))", map: Self.mapPoint)
    }

    /// Points inside a latitude/longitude box, at most `limit` of them.
    func mapPoints(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double,
                   limit: Int) throws -> [MapPoint] {
        let sql = """
            SELECT kind, row_id, title, page_title, type, lat, lng FROM (\(Self.mapPointsSQL))
            WHERE lat BETWEEN ?1 AND ?2 AND lng BETWEEN ?3 AND ?4
            ORDER BY priority, row_id LIMIT ?5
            """
        return try self.query(sql, [minLatitude, maxLatitude, minLongitude, maxLongitude, limit], map: Self.mapPoint)
    }

    /// The closest places, service stations and spots to a location (countries and regions are left out),
    /// searching up to ~1.5° away. Nearest first.
    func nearestMapPoints(latitude: Double, longitude: Double, limit: Int) throws -> [MapPoint] {
        // A degree of longitude gets shorter away from the equator.
        let longitudeScale = max(cos(latitude * .pi / 180), 0.01)
        let sql = """
            SELECT kind, row_id, title, page_title, type, lat, lng FROM (\(Self.mapPointsSQL))
            WHERE lat BETWEEN ?1 - 1.5 AND ?1 + 1.5 AND lng BETWEEN ?2 - ?3 AND ?2 + ?3
              AND (type IS NULL OR type NOT IN ('country', 'region'))
            ORDER BY (lat - ?1) * (lat - ?1) + (lng - ?2) * (lng - ?2) * ?4
            LIMIT ?5
            """
        return try self.query(sql, [latitude, longitude, 1.5 / longitudeScale, longitudeScale * longitudeScale, limit],
                              map: Self.mapPoint)
    }

    func spotDetails(rowID: Int64) throws -> SpotDetails? {
        let spotSQL = "SELECT s.page_id, p.title, s.section, s.description FROM spots s JOIN pages p ON p.id = s.page_id WHERE s.rowid = ?"
        guard let spot = try self.query(spotSQL, [rowID], map: { statement in
            (pageID: Self.int(statement, 0), pageTitle: Self.text(statement, 1) ?? "",
             path: Self.text(statement, 2) ?? "", description: Self.text(statement, 3) ?? "")
        }).first else {
            return nil
        }
        let headings = spot.path.components(separatedBy: " > ").filter { !$0.isEmpty }

        // The section the spot was written in, with its links. Fall back to the stored plain description.
        let sectionSQL = "SELECT idx, text FROM sections WHERE page_id = ? AND path = ? ORDER BY idx LIMIT 1"
        guard let section = try self.query(sectionSQL, [spot.pageID, spot.path], map: { statement in
            (index: Self.int(statement, 0), text: Self.text(statement, 1) ?? "")
        }).first, !section.text.isEmpty else {
            return SpotDetails(spotID: rowID, pageTitle: spot.pageTitle, headings: headings, text: spot.description, links: [])
        }
        let linkSQL = "SELECT start, length, target, url FROM section_links WHERE page_id = ? AND section_idx = ? AND in_heading = 0 ORDER BY start"
        let links = try self.query(linkSQL, [spot.pageID, section.index]) { statement -> PageLink? in
            let range = NSRange(location: Int(Self.int(statement, 0)), length: Int(Self.int(statement, 1)))
            if let target = Self.text(statement, 2) {
                return PageLink(range: range, destination: .page(target))
            }
            if let address = Self.text(statement, 3), let url = URL(string: address) {
                return PageLink(range: range, destination: .url(url))
            }
            return nil
        }.compactMap { $0 }
        return SpotDetails(spotID: rowID, pageTitle: spot.pageTitle, headings: headings, text: section.text, links: links)
    }

    /// The closest cities and areas to a location (no countries, service stations or spots),
    /// searching up to ~3° away. Nearest first.
    func nearestPlaces(latitude: Double, longitude: Double, limit: Int) throws -> [MapPoint] {
        let longitudeScale = max(cos(latitude * .pi / 180), 0.01)
        let sql = """
            SELECT 'page', id, title, title, infobox_type, lat, lng FROM pages
            WHERE lat IS NOT NULL AND lng IS NOT NULL
              AND lat BETWEEN ?1 - 3 AND ?1 + 3 AND lng BETWEEN ?2 - ?3 AND ?2 + ?3
              AND infobox_type NOT IN ('country', 'servicestation')
            ORDER BY (lat - ?1) * (lat - ?1) + (lng - ?2) * (lng - ?2) * ?4
            LIMIT ?5
            """
        return try self.query(sql, [latitude, longitude, 3 / longitudeScale, longitudeScale * longitudeScale, limit],
                              map: Self.mapPoint)
    }

    private static func mapPoint(_ statement: OpaquePointer) -> MapPoint {
        let kind = MapPoint.Kind(rawValue: Self.text(statement, 0) ?? "") ?? .page
        var title = Self.text(statement, 2) ?? ""
        if kind == .spot {
            // Spots store their heading path ("Hitchhiking out > West > Option 1"): keep the last heading.
            title = title.components(separatedBy: " > ").last ?? title
            if title.isEmpty {
                title = "Hitchhiking spot"
            }
        }
        return MapPoint(kind: kind, rowID: Self.int(statement, 1), title: title, pageTitle: Self.text(statement, 3) ?? "",
                        infoboxType: Self.text(statement, 4),
                        latitude: Self.double(statement, 5) ?? 0, longitude: Self.double(statement, 6) ?? 0)
    }

    // MARK: - SQLite helpers

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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

    private static func double(_ statement: OpaquePointer, _ column: Int32) -> Double? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: pointer)
    }

    /// Decodes a JSON array of strings, e.g. the `links` column.
    private static func stringArray(_ json: String?) -> [String] {
        guard let data = json?.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }
}
