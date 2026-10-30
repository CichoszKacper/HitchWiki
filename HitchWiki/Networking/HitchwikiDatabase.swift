//
//  HitchwikiDatabase.swift
//  HitchWiki
//
//  Read-only access to hitchwiki.sqlite, the database built from the Hitchwiki XML dump
//  by tools/extract.py (see tools/README.md). Uses the SQLite that ships with iOS.
//

import Foundation
import SQLite3

/// A row in the list of pages.
struct PageSummary {
    let id: Int64
    let title: String
}

/// A link inside a heading or a section's text.
struct PageLink {
    enum Destination {
        /// Another Hitchwiki article, by title (redirects already followed).
        case page(String)
        case url(URL)
    }

    /// Position in `PageSection.title` or `PageSection.text`, in UTF-16 units like NSString.
    let range: NSRange
    let destination: Destination
}

/// A heading and the plain text below it. Level 0 is the text before the first heading.
struct PageSection {
    let level: Int
    let title: String
    let text: String
    var titleLinks: [PageLink] = []
    var links: [PageLink] = []
}

/// Everything the page screen shows.
struct PageRecord {
    let id: Int64
    let title: String
    let infoboxType: String?
    /// Infobox values by field name as written on the wiki, e.g. "country", "capital", "pop".
    let infobox: [String: String]
    let sections: [PageSection]
}

enum DatabaseError: Error {
    case missingFile
    case cannotOpen(String)
    case query(String)
}

final class HitchwikiDatabase {
    static let shared: HitchwikiDatabase? = {
        do {
            return try HitchwikiDatabase(name: "hitchwiki")
        } catch {
            print("Could not open hitchwiki.sqlite: \(error)")
            return nil
        }
    }()

    private var db: OpaquePointer?
    /// SQLite runs queries one at a time on a connection.
    private let queue = DispatchQueue(label: "HitchwikiDatabase")

    init(name: String, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: name, withExtension: "sqlite") else {
            throw DatabaseError.missingFile
        }
        guard sqlite3_open_v2(url.path, &self.db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(self.db))
            sqlite3_close(self.db)
            throw DatabaseError.cannotOpen(message)
        }
    }

    deinit {
        sqlite3_close(self.db)
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
        guard let resolved = try self.resolveTitle(title),
              let row = try self.query("SELECT id, title, infobox_type FROM pages WHERE title = ?", [resolved], map: {
                  (id: Self.int($0, 0), title: Self.text($0, 1) ?? "", type: Self.text($0, 2))
              }).first else {
            return nil
        }

        var infobox = [String: String]()
        try self.query("SELECT name, value FROM infobox_fields WHERE page_id = ?", [row.id]) {
            (Self.text($0, 0) ?? "", Self.text($0, 1) ?? "")
        }.forEach { infobox[$0.0] = $0.1 }

        var sections = try self.query("SELECT level, title, text FROM sections WHERE page_id = ? ORDER BY idx", [row.id]) {
            PageSection(level: Int(Self.int($0, 0)), title: Self.text($0, 1) ?? "", text: Self.text($0, 2) ?? "")
        }

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
        for case let (section, inHeading, link)? in links where sections.indices.contains(section) {
            if inHeading {
                sections[section].titleLinks.append(link)
            } else {
                sections[section].links.append(link)
            }
        }
        return PageRecord(id: row.id, title: row.title, infoboxType: row.type, infobox: infobox, sections: sections)
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

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: pointer)
    }
}
