//
//  HitchMapView.swift
//  HitchWise
//
//  The one map view used everywhere (map tab, a page's spots, page headers): MapLibre with the HitchWise style,
//  drawing markers from a list. With `clustered`, MapLibre groups nearby markers into bubbles on the GPU, so the
//  ~55,000 points of the map tab stay smooth. Tapping a bubble zooms in; tapping a marker selects it.
//
//  Camera moves are asked for through a `MapController`, so view models can fly the map without a binding
//  that would fight the user's gestures.
//

import SwiftUI
import MapLibre
import Network

// MARK: - Model

/// An area of the map: a centre and how many degrees it spans.
struct GeoRegion: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var latitudeDelta: Double
    var longitudeDelta: Double

    init(center: CLLocationCoordinate2D, latitudeDelta: Double, longitudeDelta: Double) {
        self.latitude = center.latitude
        self.longitude = center.longitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }

    /// A square of roughly `meters` on each side.
    init(center: CLLocationCoordinate2D, meters: Double) {
        let latitudeDelta = meters / 111_000
        let longitudeDelta = meters / max(111_000 * cos(center.latitude * .pi / 180), 1_000)
        self.init(center: center, latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: self.latitude, longitude: self.longitude)
    }

    var bounds: MLNCoordinateBounds {
        MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: max(self.latitude - self.latitudeDelta / 2, -85),
                                                       longitude: self.longitude - self.longitudeDelta / 2),
                            ne: CLLocationCoordinate2D(latitude: min(self.latitude + self.latitudeDelta / 2, 85),
                                                       longitude: self.longitude + self.longitudeDelta / 2))
    }

    static let europe = GeoRegion(center: CLLocationCoordinate2D(latitude: 50, longitude: 12), latitudeDelta: 22, longitudeDelta: 22)
}

/// A point drawn on the map.
struct MapMarker: Hashable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    /// Fill colour, as "#rrggbb".
    let color: String
    /// SF Symbol drawn in white on the dot.
    let symbol: String
    /// Shown under the marker when zoomed in; nil for none.
    let title: String?
    /// Small dots (ride spots) or full markers (pages, guide spots).
    var isSmall = false
}

// MARK: - Controller

/// Moves the camera of the map it's attached to. Requests made before the map exists are kept until it does.
@MainActor
final class MapController {
    fileprivate weak var mapView: MLNMapView? {
        didSet {
            if let pending = self.pending, self.mapView != nil {
                self.pending = nil
                self.perform(pending)
            }
        }
    }

    private enum Request {
        case region(GeoRegion, animated: Bool)
        case center(CLLocationCoordinate2D, zoom: Double, animated: Bool)
    }

    private var pending: Request?

    /// Shows the whole region.
    func show(_ region: GeoRegion, animated: Bool = true) {
        self.perform(.region(region, animated: animated))
    }

    /// Centres on a coordinate at a zoom level (0 = whole world, ~15 = streets).
    func fly(to coordinate: CLLocationCoordinate2D, zoom: Double, animated: Bool = true) {
        self.perform(.center(coordinate, zoom: zoom, animated: animated))
    }

    /// Centres on the user, if their location is known. Returns false otherwise.
    @discardableResult
    func centerOnUser() -> Bool {
        guard let coordinate = self.mapView?.userLocation?.location?.coordinate, CLLocationCoordinate2DIsValid(coordinate) else {
            return false
        }
        self.fly(to: coordinate, zoom: max(self.mapView?.zoomLevel ?? 12, 12))
        return true
    }

    /// The visible area's centre, to save storage for country downloads etc.
    var visibleCenter: CLLocationCoordinate2D? {
        self.mapView?.centerCoordinate
    }

    /// Runs a request that arrived before the map had a size.
    fileprivate func performPending() {
        if let pending = self.pending {
            self.pending = nil
            self.perform(pending)
        }
    }

    private func perform(_ request: Request) {
        guard let mapView = self.mapView, mapView.bounds.width > 0 else {
            self.pending = request
            return
        }
        switch request {
        case let .region(region, animated):
            let camera = mapView.cameraThatFitsCoordinateBounds(region.bounds)
            if animated {
                mapView.fly(to: camera, withDuration: 0.9, completionHandler: nil)
            } else {
                mapView.setCamera(camera, animated: false)
            }
        case let .center(coordinate, zoom, animated):
            mapView.setCenter(coordinate, zoomLevel: zoom, animated: animated)
        }
    }
}

// MARK: - Connectivity

/// Whether the phone is online. The map uses fewer zoom levels offline (those the downloaded files have).
final class MapConnectivity: @unchecked Sendable {
    static let shared = MapConnectivity()
    static let didChange = Notification.Name("MapConnectivityDidChange")

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true

    var isOnline: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.online
    }

    func start() {
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self else {
                return
            }
            let online = path.status == .satisfied
            self.lock.lock()
            let changed = online != self.online
            self.online = online
            self.lock.unlock()
            if changed {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didChange, object: nil)
                }
            }
        }
        self.monitor.start(queue: DispatchQueue(label: "MapConnectivity"))
    }

    /// The style to load right now.
    func styleURL(dark: Bool) -> URL {
        MapStyle.url(dark: dark, offlineMaxZoom: self.isOnline ? nil : (MapPackRegistry.shared.maxZoom ?? MapStyle.onlineMaxZoom))
    }
}

// MARK: - View

struct HitchMapView: UIViewRepresentable {
    var controller: MapController?
    var markers: [MapMarker]
    /// Group nearby markers into bubbles.
    var clustered = false
    var selectedID: String?
    var initialRegion: GeoRegion?
    var showsUserLocation = false
    /// Pan, zoom and taps. Off for decorative maps such as page headers.
    var isInteractive = true
    /// Petrol stations from downloaded countries (the map's own tiles only have them zoomed right in).
    var showsFuelStations = true
    /// Called with a marker's id when tapped, or nil when the map is tapped elsewhere.
    var onSelect: ((String?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let dark = context.environment.colorScheme == .dark
        let mapView = SizedMapView(frame: .zero, styleURL: MapConnectivity.shared.styleURL(dark: dark))
        let coordinator = context.coordinator
        coordinator.mapView = mapView
        coordinator.isDark = dark
        coordinator.clustered = self.clustered
        coordinator.showsFuelStations = self.showsFuelStations
        coordinator.parent = self
        mapView.delegate = coordinator
        mapView.logoView.isHidden = true
        // The credit is shown by the app (MapAttribution) where it fits the layout.
        mapView.attributionButton.isHidden = true
        // Top right holds the app's own buttons.
        mapView.compassViewPosition = .topLeft
        mapView.compassViewMargins = CGPoint(x: 12, y: 12)
        mapView.isUserInteractionEnabled = self.isInteractive
        mapView.isPitchEnabled = false
        mapView.showsUserLocation = self.showsUserLocation
        mapView.minimumZoomLevel = 1.5
        // The camera can only fit a region once the map has a size.
        let initialRegion = self.initialRegion
        let controller = self.controller
        mapView.onFirstLayout = { [weak mapView] in
            if let mapView, let initialRegion {
                mapView.setVisibleCoordinateBounds(initialRegion.bounds, animated: false)
            }
            controller?.performPending()
        }
        if self.isInteractive {
            let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
            // Let the map's own double-tap zoom win over a single tap.
            for recognizer in mapView.gestureRecognizers ?? [] where (recognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 {
                tap.require(toFail: recognizer)
            }
            mapView.addGestureRecognizer(tap)
        }
        coordinator.observeConnectivity()
        self.controller?.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if self.controller?.mapView !== mapView {
            self.controller?.mapView = mapView
        }
        mapView.showsUserLocation = self.showsUserLocation
        let dark = context.environment.colorScheme == .dark
        if dark != coordinator.isDark {
            coordinator.isDark = dark
            coordinator.reloadStyle()
        }
        coordinator.update(markers: self.markers)
        coordinator.update(selectedID: self.selectedID)
    }

    static func dismantleUIView(_ mapView: MLNMapView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        fileprivate var parent: HitchMapView?
        fileprivate weak var mapView: MLNMapView?
        fileprivate var isDark = false

        private var markers = [MapMarker]()
        private var markersByID = [String: MapMarker]()
        fileprivate var clustered = false
        fileprivate var showsFuelStations = true
        private var fuelTask: Task<Void, Never>?
        private var selectedID: String?
        private var styleIsLoaded = false
        private var shapeTask: Task<Void, Never>?
        private var shapeRevision = 0

        private enum ID {
            static let fuel = "hw-fuel"
            static let fuelDot = "hw-fuel-dot"
            static let fuelMotorway = "hw-fuel-motorway"
            static let fuelIcon = "hw-fuel-icon"
            static let fuelName = "hw-fuel-name"
            static let markers = "hw-markers"
            static let selected = "hw-selected"
            static let clusterCircle = "hw-cluster-circle"
            static let clusterCount = "hw-cluster-count"
            static let dots = "hw-dots"
            static let markerCircle = "hw-marker-circle"
            static let markerIcon = "hw-marker-icon"
            static let markerTitle = "hw-marker-title"
            static let selectedCircle = "hw-selected-circle"
            static let selectedIcon = "hw-selected-icon"
        }

        func observeConnectivity() {
            NotificationCenter.default.addObserver(self, selector: #selector(self.connectivityChanged),
                                                   name: MapConnectivity.didChange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.packsChanged),
                                                   name: OfflineMapStore.packsDidChange, object: nil)
        }

        @objc private func packsChanged() {
            self.reloadStyle()
            if self.styleIsLoaded {
                self.applyFuelStations()
            }
        }

        @objc private func connectivityChanged() {
            self.reloadStyle()
        }

        /// Loads the style again (appearance or connection changed). Markers are added back once it's loaded.
        func reloadStyle() {
            guard let mapView = self.mapView else {
                return
            }
            let url = MapConnectivity.shared.styleURL(dark: self.isDark)
            guard mapView.styleURL != url else {
                return
            }
            self.styleIsLoaded = false
            mapView.styleURL = url
        }

        // MARK: Data

        func update(markers: [MapMarker]) {
            guard markers != self.markers else {
                return
            }
            self.markers = markers
            self.markersByID = Dictionary(markers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            if self.styleIsLoaded {
                self.applyMarkers()
                self.applySelection()
            }
        }

        func update(selectedID: String?) {
            guard selectedID != self.selectedID else {
                return
            }
            self.selectedID = selectedID
            if self.styleIsLoaded {
                self.applySelection()
            }
        }

        private func applyMarkers() {
            guard let style = self.mapView?.style, let source = style.source(withIdentifier: ID.markers) as? MLNShapeSource else {
                return
            }
            for symbol in Set(self.markers.map(\.symbol)) {
                self.registerImage(symbol, in: style)
            }
            // Building ~55,000 features takes a moment: off the main thread, keeping only the newest result.
            let markers = self.markers
            self.shapeRevision += 1
            let revision = self.shapeRevision
            self.shapeTask?.cancel()
            self.shapeTask = Task {
                let shape = await Task.detached(priority: .userInitiated) {
                    UncheckedShape(Self.shape(for: markers))
                }.value
                guard !Task.isCancelled, revision == self.shapeRevision else {
                    return
                }
                source.shape = shape.value
            }
        }

        private func applySelection() {
            guard let source = self.mapView?.style?.source(withIdentifier: ID.selected) as? MLNShapeSource else {
                return
            }
            let selected = self.selectedID.flatMap { self.markersByID[$0] }
            source.shape = Self.shape(for: selected.map { [$0] } ?? [])
        }

        nonisolated private static func shape(for markers: [MapMarker]) -> MLNShapeCollectionFeature {
            let features = markers.map { marker -> MLNPointFeature in
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
                var attributes: [String: Any] = ["id": marker.id, "color": marker.color, "symbol": marker.symbol,
                                                 "small": marker.isSmall]
                if let title = marker.title {
                    attributes["title"] = title
                }
                feature.attributes = attributes
                return feature
            }
            return MLNShapeCollectionFeature(shapes: features)
        }

        // MARK: Style

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated {
                if self.showsFuelStations {
                    self.installFuelLayers(in: style)
                }
                self.installLayers(in: style)
                self.styleIsLoaded = true
                self.applyMarkers()
                self.applySelection()
                self.applyFuelStations()
            }
        }

        private func installLayers(in style: MLNStyle) {
            for symbol in Set(self.markers.map(\.symbol)).union(["hand.thumbsup.fill"]) {
                self.registerImage(symbol, in: style)
            }

            let markers = MLNShapeSource(identifier: ID.markers, shape: nil, options: [
                .clustered: self.clustered,
                .clusterRadius: 44,
                .maximumZoomLevelForClustering: 14
            ])
            style.addSource(markers)
            let selected = MLNShapeSource(identifier: ID.selected, shape: nil, options: nil)
            style.addSource(selected)

            let accent = UIColor(named: "AccentColor") ?? .systemOrange
            let isCluster = NSPredicate(format: "cluster == YES")
            let isPoint = NSPredicate(format: "cluster != YES")

            if self.clustered {
                let circle = MLNCircleStyleLayer(identifier: ID.clusterCircle, source: markers)
                circle.predicate = isCluster
                circle.circleColor = NSExpression(forConstantValue: accent)
                circle.circleOpacity = NSExpression(forConstantValue: 0.92)
                circle.circleRadius = NSExpression(mglJSONObject: ["step", ["get", "point_count"], 16, 25, 20, 250, 25, 2500, 31])
                circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                circle.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
                style.addLayer(circle)

                let count = MLNSymbolStyleLayer(identifier: ID.clusterCount, source: markers)
                count.predicate = isCluster
                count.text = NSExpression(mglJSONObject: ["get", "point_count_abbreviated"])
                count.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
                count.textFontSize = NSExpression(forConstantValue: 13)
                count.textColor = NSExpression(forConstantValue: UIColor.white)
                count.textAllowsOverlap = NSExpression(forConstantValue: true)
                count.textIgnoresPlacement = NSExpression(forConstantValue: true)
                style.addLayer(count)
            }

            // Ride spots: small dots coloured by rating.
            let dots = MLNCircleStyleLayer(identifier: ID.dots, source: markers)
            dots.predicate = NSPredicate(format: "cluster != YES AND small == YES")
            dots.circleColor = NSExpression(mglJSONObject: ["to-color", ["get", "color"]])
            dots.circleRadius = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 10, 5, 16, 9])
            dots.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            dots.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(dots)

            // Places and the guide's spots: a bigger dot with an icon, and the name below when zoomed in.
            let fullPoint = NSPredicate(format: "cluster != YES AND small != YES")
            let circle = MLNCircleStyleLayer(identifier: ID.markerCircle, source: markers)
            circle.predicate = fullPoint
            circle.circleColor = NSExpression(mglJSONObject: ["to-color", ["get", "color"]])
            circle.circleRadius = NSExpression(forConstantValue: 13)
            circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            circle.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
            style.addLayer(circle)

            let icon = MLNSymbolStyleLayer(identifier: ID.markerIcon, source: markers)
            icon.predicate = fullPoint
            icon.iconImageName = NSExpression(mglJSONObject: ["get", "symbol"])
            icon.iconAllowsOverlap = NSExpression(forConstantValue: true)
            icon.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(icon)

            let title = MLNSymbolStyleLayer(identifier: ID.markerTitle, source: markers)
            title.predicate = isPoint
            title.minimumZoomLevel = 11
            title.text = NSExpression(mglJSONObject: ["coalesce", ["get", "title"], ""])
            title.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            title.textFontSize = NSExpression(forConstantValue: 12)
            title.textAnchor = NSExpression(forConstantValue: "top")
            title.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.4)))
            title.maximumTextWidth = NSExpression(forConstantValue: 9)
            title.textColor = NSExpression(forConstantValue: self.isDark ? UIColor.white : UIColor(white: 0.1, alpha: 1))
            title.textHaloColor = NSExpression(forConstantValue: self.isDark ? UIColor.black : UIColor.white)
            title.textHaloWidth = NSExpression(forConstantValue: 1.5)
            title.textOptional = NSExpression(forConstantValue: true)
            style.addLayer(title)

            // The selected point, larger and on top of everything.
            let selectedCircle = MLNCircleStyleLayer(identifier: ID.selectedCircle, source: selected)
            selectedCircle.circleColor = NSExpression(mglJSONObject: ["to-color", ["get", "color"]])
            selectedCircle.circleRadius = NSExpression(forConstantValue: 19)
            selectedCircle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            selectedCircle.circleStrokeWidth = NSExpression(forConstantValue: 3.5)
            style.addLayer(selectedCircle)

            let selectedIcon = MLNSymbolStyleLayer(identifier: ID.selectedIcon, source: selected)
            selectedIcon.iconImageName = NSExpression(mglJSONObject: ["get", "symbol"])
            selectedIcon.iconScale = NSExpression(forConstantValue: 1.3)
            selectedIcon.iconAllowsOverlap = NSExpression(forConstantValue: true)
            selectedIcon.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(selectedIcon)
        }

        /// Petrol stations under the spots: small blue dots, and bigger ones with a pump at motorway services,
        /// shown from further out because that's where hitchhikers plan long rides.
        private func installFuelLayers(in style: MLNStyle) {
            self.registerImage("fuelpump.fill", in: style)
            let source = MLNShapeSource(identifier: ID.fuel, shape: nil, options: nil)
            style.addSource(source)
            let blue = self.isDark ? UIColor(red: 0.36, green: 0.61, blue: 1, alpha: 1) : UIColor(red: 0.17, green: 0.44, blue: 0.84, alpha: 1)
            let halo = self.isDark ? UIColor(white: 0.1, alpha: 1) : UIColor.white

            let dot = MLNCircleStyleLayer(identifier: ID.fuelDot, source: source)
            dot.predicate = NSPredicate(format: "motorway != YES")
            dot.minimumZoomLevel = 10
            dot.circleColor = NSExpression(forConstantValue: blue)
            dot.circleRadius = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 10, 2.5, 16, 6])
            dot.circleStrokeColor = NSExpression(forConstantValue: halo)
            dot.circleStrokeWidth = NSExpression(forConstantValue: 1.2)
            style.addLayer(dot)

            let motorway = MLNCircleStyleLayer(identifier: ID.fuelMotorway, source: source)
            motorway.predicate = NSPredicate(format: "motorway == YES")
            motorway.minimumZoomLevel = 7
            motorway.circleColor = NSExpression(forConstantValue: blue)
            motorway.circleRadius = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 7, 3, 10, 7, 16, 11])
            motorway.circleStrokeColor = NSExpression(forConstantValue: halo)
            motorway.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            style.addLayer(motorway)

            let icon = MLNSymbolStyleLayer(identifier: ID.fuelIcon, source: source)
            icon.predicate = NSPredicate(format: "motorway == YES")
            icon.minimumZoomLevel = 10
            icon.iconImageName = NSExpression(forConstantValue: "fuelpump.fill")
            icon.iconScale = NSExpression(forConstantValue: 0.75)
            icon.iconAllowsOverlap = NSExpression(forConstantValue: true)
            icon.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(icon)

            let name = MLNSymbolStyleLayer(identifier: ID.fuelName, source: source)
            name.minimumZoomLevel = 13
            name.text = NSExpression(mglJSONObject: ["coalesce", ["get", "name"], ""])
            name.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            name.textFontSize = NSExpression(forConstantValue: 11)
            name.textAnchor = NSExpression(forConstantValue: "top")
            name.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 0.9)))
            name.textColor = NSExpression(forConstantValue: blue)
            name.textHaloColor = NSExpression(forConstantValue: halo)
            name.textHaloWidth = NSExpression(forConstantValue: 1.2)
            name.textOptional = NSExpression(forConstantValue: true)
            style.addLayer(name)
        }

        /// Fills the petrol station layer from the downloaded countries (read off the main thread).
        private func applyFuelStations() {
            guard self.showsFuelStations,
                  let source = self.mapView?.style?.source(withIdentifier: ID.fuel) as? MLNShapeSource else {
                return
            }
            self.fuelTask?.cancel()
            self.fuelTask = Task {
                let shape = await Task.detached(priority: .utility) {
                    let features = MapPackRegistry.shared.fuelStations().map { station -> MLNPointFeature in
                        let feature = MLNPointFeature()
                        feature.coordinate = CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
                        var attributes: [String: Any] = ["motorway": station.isMotorway]
                        if let name = station.name {
                            attributes["name"] = name
                        }
                        feature.attributes = attributes
                        return feature
                    }
                    return UncheckedShape(MLNShapeCollectionFeature(shapes: features))
                }.value
                guard !Task.isCancelled else {
                    return
                }
                source.shape = shape.value
            }
        }

        /// A white SF Symbol, the icon drawn on markers.
        private func registerImage(_ symbol: String, in style: MLNStyle) {
            guard style.image(forName: symbol) == nil else {
                return
            }
            let configuration = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            guard let image = UIImage(systemName: symbol, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else {
                return
            }
            style.setImage(image, forName: symbol)
        }

        // MARK: Taps

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = self.mapView, recognizer.state == .ended else {
                return
            }
            let point = recognizer.location(in: mapView)
            let area = CGRect(x: point.x - 18, y: point.y - 18, width: 36, height: 36)
            let layers: Set<String> = [ID.clusterCircle, ID.dots, ID.markerCircle, ID.markerIcon, ID.selectedCircle]
            let features = mapView.visibleFeatures(in: area, styleLayerIdentifiers: layers)
            // Nearest to the finger first.
            let nearest = features.min { lhs, rhs in
                let a = mapView.convert(lhs.coordinate, toPointTo: mapView)
                let b = mapView.convert(rhs.coordinate, toPointTo: mapView)
                return hypot(a.x - point.x, a.y - point.y) < hypot(b.x - point.x, b.y - point.y)
            }
            if let cluster = nearest as? MLNPointFeatureCluster,
               let source = mapView.style?.source(withIdentifier: ID.markers) as? MLNShapeSource {
                let zoom = min(source.zoomLevel(forExpanding: cluster), 16)
                mapView.setCenter(cluster.coordinate, zoomLevel: max(zoom, mapView.zoomLevel + 1), animated: true)
                return
            }
            if let id = nearest?.attribute(forKey: "id") as? String {
                self.parent?.onSelect?(id)
            } else {
                self.parent?.onSelect?(nil)
            }
        }
    }
}

/// Tells when it first gets a size, so camera moves asked for earlier can run.
private final class SizedMapView: MLNMapView {
    var onFirstLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if self.bounds.width > 0, self.bounds.height > 0, let onFirstLayout = self.onFirstLayout {
            self.onFirstLayout = nil
            onFirstLayout()
        }
    }
}

/// Carries a MapLibre shape (not Sendable) from the background task that builds it.
private struct UncheckedShape: @unchecked Sendable {
    let value: MLNShape
    init(_ value: MLNShape) {
        self.value = value
    }
}

extension UIColor {
    /// "#rrggbb", for map styles.
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        self.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }
}
