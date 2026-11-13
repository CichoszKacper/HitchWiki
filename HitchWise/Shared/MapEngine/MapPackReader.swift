//
//  MapPackReader.swift
//  HitchWise
//
//  Reads map tiles from downloaded country files (MBTiles: SQLite with one row per tile). The files are cut
//  from OpenFreeMap's planet, so they hold the same tiles the map loads online (see tools/build_map_packs.py).
//
//  `MapPackRegistry` is what the tile loader asks: it is called from MapLibre's network threads, so it is
//  thread-safe and does no main-actor work.
//

import Foundation
import SQLite3

/// One downloaded country file, open for reading.
final class MapPackReader: @unchecked Sendable {
    let id: String
    /// West, south, east, north in degrees.
    let bounds: (west: Double, south: Double, east: Double, north: Double)
    let maxZoom: Int

    private let handle: OpaquePointer
    private let lock = NSLock()
    private var statement: OpaquePointer?

    init?(id: String, url: URL) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let handle else {
            sqlite3_close(handle)
            return nil
        }
        self.id = id
        self.handle = handle

        var metadata = [String: String]()
        var query: OpaquePointer?
        if sqlite3_prepare_v2(handle, "SELECT name, value FROM metadata", -1, &query, nil) == SQLITE_OK {
            while sqlite3_step(query) == SQLITE_ROW {
                if let name = sqlite3_column_text(query, 0), let value = sqlite3_column_text(query, 1) {
                    metadata[String(cString: name)] = String(cString: value)
                }
            }
        }
        sqlite3_finalize(query)

        let numbers = (metadata["bounds"] ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        self.bounds = numbers.count == 4 ? (numbers[0], numbers[1], numbers[2], numbers[3]) : (-180, -85.06, 180, 85.06)
        self.maxZoom = Int(metadata["maxzoom"] ?? "") ?? 13

        guard sqlite3_prepare_v2(handle, "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?",
                                 -1, &self.statement, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
    }

    deinit {
        sqlite3_finalize(self.statement)
        sqlite3_close(self.handle)
    }

    /// Whether the tile at z/x/y overlaps this file's area.
    func covers(z: Int, x: Int, y: Int) -> Bool {
        guard z <= self.maxZoom else {
            return false
        }
        let tile = TileMath.bounds(z: z, x: x, y: y)
        return tile.west <= self.bounds.east && tile.east >= self.bounds.west
            && tile.south <= self.bounds.north && tile.north >= self.bounds.south
    }

    /// The tile's vector data (uncompressed), or nil if the file doesn't have it.
    func tile(z: Int, x: Int, y: Int) -> Data? {
        guard self.covers(z: z, x: x, y: y) else {
            return nil
        }
        // MBTiles counts rows from the bottom (TMS); the map counts from the top.
        let row = (1 << z) - 1 - y
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let statement = self.statement else {
            return nil
        }
        defer { sqlite3_reset(statement) }
        sqlite3_bind_int(statement, 1, Int32(z))
        sqlite3_bind_int(statement, 2, Int32(x))
        sqlite3_bind_int(statement, 3, Int32(row))
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            return nil
        }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        return Gzip.decompressIfNeeded(data)
    }
}

/// The country files the map currently reads from.
final class MapPackRegistry: @unchecked Sendable {
    static let shared = MapPackRegistry()

    private let lock = NSLock()
    private var readers = [MapPackReader]()

    /// Opens these files (id → path), closing any that are no longer listed.
    func use(_ packs: [String: URL]) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var kept = self.readers.filter { packs[$0.id] != nil }
        for (id, url) in packs where !kept.contains(where: { $0.id == id }) {
            if let reader = MapPackReader(id: id, url: url) {
                kept.append(reader)
            }
        }
        self.readers = kept
    }

    var isEmpty: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.readers.isEmpty
    }

    /// Highest zoom every downloaded file has; the map stops there while offline and enlarges those tiles.
    var maxZoom: Int? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.readers.map(\.maxZoom).min()
    }

    func tile(z: Int, x: Int, y: Int) -> Data? {
        self.lock.lock()
        let readers = self.readers
        self.lock.unlock()
        for reader in readers {
            if let data = reader.tile(z: z, x: x, y: y) {
                return data
            }
        }
        return nil
    }

    /// Whether a downloaded file covers this coordinate.
    func covers(latitude: Double, longitude: Double) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.readers.contains {
            longitude >= $0.bounds.west && longitude <= $0.bounds.east && latitude >= $0.bounds.south && latitude <= $0.bounds.north
        }
    }
}

enum TileMath {
    /// The area a web-mercator tile covers, in degrees.
    static func bounds(z: Int, x: Int, y: Int) -> (west: Double, south: Double, east: Double, north: Double) {
        let n = Double(1 << z)
        func latitude(_ y: Double) -> Double {
            atan(sinh(.pi * (1 - 2 * y / n))) * 180 / .pi
        }
        return (Double(x) / n * 360 - 180, latitude(Double(y + 1)), Double(x + 1) / n * 360 - 180, latitude(Double(y)))
    }
}

/// MBTiles usually store tiles gzipped. MapLibre wants them plain when they don't come over HTTP.
enum Gzip {
    static func decompressIfNeeded(_ data: Data) -> Data {
        guard data.count > 18 else {
            return data
        }
        let bytes = [UInt8](data.prefix(10))
        if bytes[0] == 0x1f && bytes[1] == 0x8b {
            return self.gunzip(data) ?? data
        }
        // zlib header: 0x78 followed by a check byte.
        if bytes[0] == 0x78 && (UInt16(bytes[0]) << 8 | UInt16(bytes[1])) % 31 == 0 {
            let deflate = data.dropFirst(2).dropLast(4)
            return (try? (Data(deflate) as NSData).decompressed(using: .zlib) as Data) ?? data
        }
        return data
    }

    private static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {   // FEXTRA
            guard bytes.count > offset + 2 else { return nil }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        if flags & 0x08 != 0 {   // FNAME
            while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {   // FCOMMENT
            while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 {   // FHCRC
            offset += 2
        }
        guard offset < bytes.count - 8 else {
            return nil
        }
        // What's left is raw DEFLATE, which is what NSData's .zlib algorithm reads, then an 8-byte trailer.
        let deflate = Data(bytes[offset..<(bytes.count - 8)])
        return try? (deflate as NSData).decompressed(using: .zlib) as Data
    }
}
