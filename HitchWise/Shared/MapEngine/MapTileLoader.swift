//
//  MapTileLoader.swift
//  HitchWise
//
//  Every map request MapLibre makes goes to a made-up host, `tiles.hitchwise.invalid`, and this URL protocol
//  answers it:
//   - map tiles from a downloaded country file when one covers the tile, otherwise from OpenFreeMap;
//   - label fonts from the copies in the app (MapGlyphs), otherwise from OpenFreeMap.
//  So the same map style works online and offline, and OpenFreeMap is only asked for what isn't on the phone.
//
//  OpenFreeMap asks apps to identify themselves with their own User-Agent; every request here sends one.
//

import Foundation
import MapLibre
import UIKit

final class MapTileLoader: URLProtocol, @unchecked Sendable {
    static let host = "tiles.hitchwise.invalid"
    static let tileURLTemplate = "https://\(host)/planet/{z}/{x}/{y}.pbf"
    static let glyphsURLTemplate = "https://\(host)/fonts/{fontstack}/{range}.pbf"

    private static let openFreeMap = URL(string: "https://tiles.openfreemap.org")!

    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "HitchWise/\(version) (iOS; hitchhiking guide app)"
    }()

    /// Fetches what isn't on the phone. OpenFreeMap asks for at most a few requests at a time.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": MapTileLoader.userAgent]
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    /// Call once at launch, before any map is created.
    static func install() {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MapTileLoader.self] + (configuration.protocolClasses ?? [])
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        MLNNetworkConfiguration.sharedManager.sessionConfiguration = configuration
    }

    private var dataTask: URLSessionDataTask?
    private var isStopped = false
    private let stateLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == Self.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = self.request.url else {
            self.fail()
            return
        }
        let parts = url.path.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        DispatchQueue.global(qos: .userInitiated).async {
            switch parts.first {
            case "planet"?:
                self.loadTile(parts)
            case "fonts"?:
                self.loadGlyphs(parts)
            default:
                self.fail()
            }
        }
    }

    override func stopLoading() {
        self.stateLock.lock()
        self.isStopped = true
        let task = self.dataTask
        self.stateLock.unlock()
        task?.cancel()
    }

    // MARK: - Tiles

    private func loadTile(_ parts: [String]) {
        // planet / z / x / y.pbf
        guard parts.count == 4, let z = Int(parts[1]), let x = Int(parts[2]),
              let y = Int(parts[3].replacingOccurrences(of: ".pbf", with: "")) else {
            self.fail()
            return
        }
        if let data = MapPackRegistry.shared.tile(z: z, x: x, y: y) {
            self.respond(with: data, contentType: "application/x-protobuf")
            return
        }
        let remote = Self.openFreeMap.appending(path: "planet/latest/\(z)/\(x)/\(y).pbf")
        self.fetch(remote) { data in
            // An empty tile (open sea) is fine; MapLibre draws nothing there.
            self.respond(with: data ?? Data(), contentType: "application/x-protobuf")
        }
    }

    // MARK: - Fonts

    private func loadGlyphs(_ parts: [String]) {
        // fonts / Noto Sans Regular / 0-255.pbf
        guard parts.count == 3 else {
            self.fail()
            return
        }
        let fontstack = parts[1]
        let range = parts[2]
        if let local = Bundle.main.url(forResource: range.replacingOccurrences(of: ".pbf", with: ""), withExtension: "pbf",
                                       subdirectory: "MapGlyphs/\(fontstack)"),
           let data = try? Data(contentsOf: local) {
            self.respond(with: data, contentType: "application/x-protobuf")
            return
        }
        let remote = Self.openFreeMap.appending(path: "fonts/\(fontstack)/\(range)")
        self.fetch(remote, failSilently: true) { data in
            // Offline: no letters for this script rather than an error that holds up the labels.
            self.respond(with: data ?? Data(), contentType: "application/x-protobuf")
        }
    }

    // MARK: - Plumbing

    /// Calls `completion` with the body of a successful response, nil when the server had nothing (404).
    /// Network errors fail the request so MapLibre tries again once the connection is back.
    private func fetch(_ url: URL, failSilently: Bool = false, completion: @escaping @Sendable (Data?) -> Void) {
        let task = Self.session.dataTask(with: url) { data, response, error in
            if let error {
                if failSilently {
                    completion(nil)
                } else {
                    self.fail(error)
                }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                completion(data)
            } else if status == 404 || status == 204 {
                completion(nil)
            } else if failSilently {
                completion(nil)
            } else {
                self.fail()
            }
        }
        self.stateLock.lock()
        guard !self.isStopped else {
            self.stateLock.unlock()
            return
        }
        self.dataTask = task
        self.stateLock.unlock()
        task.resume()
    }

    private func respond(with data: Data, contentType: String) {
        guard let url = self.request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": contentType,
                                                            "Content-Length": "\(data.count)",
                                                            "Cache-Control": "max-age=604800"]) else {
            self.fail()
            return
        }
        guard self.isActive else {
            return
        }
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: data)
        self.client?.urlProtocolDidFinishLoading(self)
    }

    private func fail(_ error: Error = URLError(.cannotLoadFromNetwork)) {
        guard self.isActive else {
            return
        }
        self.client?.urlProtocol(self, didFailWithError: error)
    }

    private var isActive: Bool {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        return !self.isStopped
    }
}
