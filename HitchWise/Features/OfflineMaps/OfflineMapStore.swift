//
//  OfflineMapStore.swift
//  HitchWise
//
//  Downloadable country maps. A catalogue (`index.json`) and one MBTiles file per country sit next to each other
//  on the file host set in Info.plist (`HWMapPacksBaseURL`, e.g. a Cloudflare R2 bucket). tools/build_map_packs.py
//  makes both. Downloaded files live in Application Support/MapPacks and are read by MapPackRegistry.
//
//  Downloads are free for now. `requiresPurchase` is the one place to change when offline maps become paid.
//

import Foundation
import Observation

/// A country in the catalogue.
struct MapPackInfo: Codable, Hashable, Identifiable, Sendable {
    /// ISO country code, e.g. "PL".
    let id: String
    /// English name, used when the system doesn't know the code.
    let name: String
    /// West, south, east, north.
    let bbox: [Double]
    let bytes: Int64
    /// File name next to index.json.
    let file: String

    var displayName: String {
        Locale.current.localizedString(forRegionCode: self.id) ?? self.name
    }

    /// The country's flag, made from its code.
    var flag: String {
        guard self.id.count == 2 else {
            return "🗺️"
        }
        return String(String.UnicodeScalarView(self.id.uppercased().unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        self.bbox.count == 4 && longitude >= self.bbox[0] && latitude >= self.bbox[1] && longitude <= self.bbox[2] && latitude <= self.bbox[3]
    }
}

private struct MapPackCatalog: Codable {
    /// OpenFreeMap build the files were cut from, e.g. "20261101_080013_pt".
    let version: String
    let maxzoom: Int
    let packs: [MapPackInfo]
}

/// A downloaded country and which build it came from.
struct InstalledMapPack: Codable, Hashable, Sendable {
    let info: MapPackInfo
    let version: String
}

@MainActor
@Observable
final class OfflineMapStore {
    static let shared = OfflineMapStore()
    /// Posted when files are added or removed, so maps reload their tiles.
    static let packsDidChange = Notification.Name("OfflineMapPacksDidChange")

    enum CatalogState: Equatable {
        case idle, loading, loaded, failed
        /// No file host set up yet.
        case unavailable
    }

    private(set) var catalog = [MapPackInfo]()
    private(set) var catalogVersion: String?
    private(set) var catalogState = CatalogState.idle
    private(set) var installed = [String: InstalledMapPack]()
    /// Downloads in progress, 0...1.
    private(set) var progress = [String: Double]()
    private(set) var failedDownloads = Set<String>()

    /// Offline maps are free for now. Return true here for packs that should need a purchase.
    func requiresPurchase(_ pack: MapPackInfo) -> Bool {
        false
    }

    @ObservationIgnored private let baseURL: URL?
    @ObservationIgnored private lazy var downloader = PackDownloader(store: self)

    static let directory: URL = {
        let url = URL.applicationSupportDirectory.appending(path: "MapPacks", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = url
        try? excluded.setResourceValues(values)
        return url
    }()

    private static var manifestURL: URL {
        self.directory.appending(path: "installed.json")
    }

    private init() {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "HWMapPacksBaseURL") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        self.baseURL = configured.isEmpty ? nil : URL(string: configured.hasSuffix("/") ? configured : configured + "/")
        if let data = try? Data(contentsOf: Self.manifestURL),
           let packs = try? JSONDecoder().decode([InstalledMapPack].self, from: data) {
            self.installed = Dictionary(packs.map { ($0.info.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        self.registerFiles(notify: false)
    }

    /// Call at launch: opens the downloaded files so the map can use them straight away.
    func start() {}

    var installedPacks: [InstalledMapPack] {
        self.installed.values.sorted { $0.info.displayName < $1.info.displayName }
    }

    var installedBytes: Int64 {
        self.installed.values.reduce(0) { $0 + $1.info.bytes }
    }

    func isUpdateAvailable(_ id: String) -> Bool {
        guard let installed = self.installed[id], let version = self.catalogVersion else {
            return false
        }
        return installed.version != version && self.catalog.contains { $0.id == id }
    }

    // MARK: - Catalogue

    func loadCatalog() async {
        guard let baseURL = self.baseURL else {
            self.catalogState = .unavailable
            return
        }
        guard self.catalogState != .loading else {
            return
        }
        self.catalogState = .loading
        do {
            var request = URLRequest(url: baseURL.appending(path: "index.json"))
            request.cachePolicy = .reloadRevalidatingCacheData
            request.setValue(MapTileLoader.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let catalog = try JSONDecoder().decode(MapPackCatalog.self, from: data)
            self.catalog = catalog.packs.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            self.catalogVersion = catalog.version
            self.catalogState = .loaded
        } catch {
            self.catalogState = self.catalog.isEmpty ? .failed : .loaded
        }
    }

    // MARK: - Downloads

    func download(_ pack: MapPackInfo) {
        guard let baseURL = self.baseURL, self.progress[pack.id] == nil, !self.requiresPurchase(pack) else {
            return
        }
        self.failedDownloads.remove(pack.id)
        self.progress[pack.id] = 0
        self.downloader.start(id: pack.id, url: baseURL.appending(path: pack.file))
    }

    func cancelDownload(_ id: String) {
        self.downloader.cancel(id: id)
        self.progress[id] = nil
    }

    func delete(_ id: String) {
        self.installed[id] = nil
        self.saveManifest()
        self.registerFiles(notify: true)
        try? FileManager.default.removeItem(at: Self.fileURL(for: id))
    }

    fileprivate func downloadProgressed(id: String, fraction: Double) {
        if self.progress[id] != nil {
            self.progress[id] = fraction
        }
    }

    /// The file has been moved to `temporary`; check it opens, then put it in place.
    fileprivate func downloadFinished(id: String, temporary: URL?) {
        self.progress[id] = nil
        guard let temporary, let pack = self.catalog.first(where: { $0.id == id }), let version = self.catalogVersion,
              MapPackReader(id: id, url: temporary) != nil else {
            if let temporary {
                try? FileManager.default.removeItem(at: temporary)
            }
            self.failedDownloads.insert(id)
            return
        }
        let destination = Self.fileURL(for: id)
        // Close the old file before replacing it (an update).
        MapPackRegistry.shared.use(self.files(excluding: id))
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            self.failedDownloads.insert(id)
            self.registerFiles(notify: false)
            return
        }
        self.installed[id] = InstalledMapPack(info: pack, version: version)
        self.saveManifest()
        self.registerFiles(notify: true)
    }

    // MARK: - Files

    private static func fileURL(for id: String) -> URL {
        self.directory.appending(path: "\(id).mbtiles")
    }

    private func files(excluding excluded: String? = nil) -> [String: URL] {
        var files = [String: URL]()
        for id in self.installed.keys where id != excluded {
            let url = Self.fileURL(for: id)
            if FileManager.default.fileExists(atPath: url.path) {
                files[id] = url
            }
        }
        return files
    }

    private func registerFiles(notify: Bool) {
        let files = self.files()
        // Opening SQLite files is quick, but keep it off the main thread's critical path anyway.
        Task.detached(priority: .userInitiated) {
            MapPackRegistry.shared.use(files)
            if notify {
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.packsDidChange, object: nil)
                }
            }
        }
    }

    private func saveManifest() {
        if let data = try? JSONEncoder().encode(Array(self.installed.values)) {
            try? data.write(to: Self.manifestURL, options: .atomic)
        }
    }
}

/// Downloads country files with progress. Files are large (tens to hundreds of MB), so each one is
/// written to disk as it arrives rather than kept in memory.
private final class PackDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private weak var store: OfflineMapStore?
    private let lock = NSLock()
    private var tasks = [Int: String]()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": MapTileLoader.userAgent]
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(store: OfflineMapStore) {
        self.store = store
    }

    func start(id: String, url: URL) {
        let task = self.session.downloadTask(with: url)
        self.lock.lock()
        self.tasks[task.taskIdentifier] = id
        self.lock.unlock()
        task.resume()
    }

    func cancel(id: String) {
        self.lock.lock()
        let identifiers = self.tasks.filter { $0.value == id }.map(\.key)
        identifiers.forEach { self.tasks[$0] = nil }
        self.lock.unlock()
        self.session.getAllTasks { tasks in
            tasks.filter { identifiers.contains($0.taskIdentifier) }.forEach { $0.cancel() }
        }
    }

    private func id(for task: URLSessionTask) -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.tasks[task.taskIdentifier]
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = self.id(for: downloadTask), totalBytesExpectedToWrite > 0 else {
            return
        }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor [weak store] in
            store?.downloadProgressed(id: id, fraction: fraction)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = self.id(for: downloadTask) else {
            return
        }
        // The system deletes `location` when this returns: move it somewhere of ours first.
        var moved: URL?
        if (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 {
            let temporary = OfflineMapStore.directory.appending(path: "\(id).download")
            try? FileManager.default.removeItem(at: temporary)
            if (try? FileManager.default.moveItem(at: location, to: temporary)) != nil {
                moved = temporary
            }
        }
        self.lock.lock()
        self.tasks[downloadTask.taskIdentifier] = nil
        self.lock.unlock()
        let result = moved
        Task { @MainActor [weak store] in
            store?.downloadFinished(id: id, temporary: result)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil, let id = self.id(for: task) else {
            return
        }
        self.lock.lock()
        self.tasks[task.taskIdentifier] = nil
        self.lock.unlock()
        Task { @MainActor [weak store] in
            store?.downloadFinished(id: id, temporary: nil)
        }
    }
}
