//
//  HitchMapView.swift
//  HitchWise
//
//  The Map tab's map, as UIKit's MKMapView instead of SwiftUI's Map.
//
//  Why: offline, in areas MapKit has no tiles for, SwiftUI's Map can stop taking touches
//  (no panning, zooming or tapping, seen after selecting and closing a marker fully zoomed in,
//  in Airplane Mode). MapKit also hides overlays there, so an invisible overlay can't hold the
//  touches. MKMapView receives touches through normal UIView hit-testing on its frame, whatever is
//  drawn inside it.
//
//  The view model still does the clustering; this view only mirrors its singles and clusters as
//  annotations, reports selection and camera changes, and flies to `cameraMove`.
//

import SwiftUI
import MapKit

struct HitchMapView: UIViewRepresentable {
    let singles: [MapPoint]
    let clusters: [MapCluster]
    @Binding var selectedID: String?
    let cameraMove: CameraMove?
    /// Offline the map is flat: realistic 3D terrain needs data too.
    let isOnline: Bool
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onClusterTap: (MapCluster) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false   // its own button below, under the location button
        map.showsScale = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.pointReuseID)
        map.register(ClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuseID)

        // Location and compass buttons, top right, like SwiftUI's MapUserLocationButton and MapCompass.
        let locationButton = MKUserTrackingButton(mapView: map)
        locationButton.backgroundColor = .systemBackground.withAlphaComponent(0.92)
        locationButton.layer.cornerRadius = 10
        locationButton.layer.cornerCurve = .continuous
        locationButton.layer.shadowColor = UIColor.black.cgColor
        locationButton.layer.shadowOpacity = 0.12
        locationButton.layer.shadowRadius = 6
        locationButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .adaptive
        for control in [locationButton, compass] as [UIView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            map.addSubview(control)
        }
        NSLayoutConstraint.activate([
            locationButton.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 8),
            locationButton.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            locationButton.widthAnchor.constraint(equalToConstant: 44),
            locationButton.heightAnchor.constraint(equalToConstant: 44),
            compass.topAnchor.constraint(equalTo: locationButton.bottomAnchor, constant: 10),
            compass.centerXAnchor.constraint(equalTo: locationButton.centerXAnchor)
        ])

        context.coordinator.apply(isOnline: self.isOnline, to: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.apply(isOnline: self.isOnline, to: map)
        coordinator.syncAnnotations(singles: self.singles, clusters: self.clusters, on: map)
        coordinator.syncSelection(self.selectedID, on: map)
        coordinator.apply(cameraMove: self.cameraMove, to: map)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        static let pointReuseID = "point"
        static let clusterReuseID = "cluster"

        var parent: HitchMapView
        private var pointAnnotations = [String: PointAnnotation]()
        private var clusterAnnotations = [String: ClusterAnnotation]()
        private var appliedMoveID: UUID?
        private var appliedOnline: Bool?
        /// Set while the code (not the user) changes the selection, so the delegate doesn't echo it back.
        private var isSyncingSelection = false

        init(parent: HitchMapView) {
            self.parent = parent
        }

        func apply(isOnline: Bool, to map: MKMapView) {
            guard self.appliedOnline != isOnline else {
                return
            }
            self.appliedOnline = isOnline
            let configuration = MKStandardMapConfiguration(elevationStyle: isOnline ? .realistic : .flat)
            configuration.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = configuration
        }

        func apply(cameraMove: CameraMove?, to map: MKMapView) {
            guard let cameraMove, cameraMove.id != self.appliedMoveID else {
                return
            }
            let animated = cameraMove.animated && self.appliedMoveID != nil
            self.appliedMoveID = cameraMove.id
            map.setRegion(map.regionThatFits(cameraMove.region), animated: animated)
        }

        /// Adds and removes annotations so the map shows exactly the view model's singles and clusters.
        func syncAnnotations(singles: [MapPoint], clusters: [MapCluster], on map: MKMapView) {
            var removed = [MKAnnotation]()
            var added = [MKAnnotation]()

            let wantedPoints = Dictionary(singles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, annotation) in self.pointAnnotations where wantedPoints[id] == nil {
                removed.append(annotation)
                self.pointAnnotations[id] = nil
            }
            for (id, point) in wantedPoints where self.pointAnnotations[id] == nil {
                let annotation = PointAnnotation(point: point)
                self.pointAnnotations[id] = annotation
                added.append(annotation)
            }

            // A cluster keeps its id while panning but its count and centre can change: replace it then.
            let wantedClusters = Dictionary(clusters.map { (ClusterAnnotation.key(for: $0), $0) },
                                            uniquingKeysWith: { first, _ in first })
            for (key, annotation) in self.clusterAnnotations where wantedClusters[key] == nil {
                removed.append(annotation)
                self.clusterAnnotations[key] = nil
            }
            for (key, cluster) in wantedClusters where self.clusterAnnotations[key] == nil {
                let annotation = ClusterAnnotation(cluster: cluster)
                self.clusterAnnotations[key] = annotation
                added.append(annotation)
            }

            if !removed.isEmpty {
                map.removeAnnotations(removed)
            }
            if !added.isEmpty {
                map.addAnnotations(added)
            }
        }

        func syncSelection(_ selectedID: String?, on map: MKMapView) {
            let current = map.selectedAnnotations.compactMap { $0 as? PointAnnotation }.first
            guard current?.point.id != selectedID else {
                return
            }
            self.isSyncingSelection = true
            defer { self.isSyncingSelection = false }
            if let current {
                map.deselectAnnotation(current, animated: true)
            }
            if let selectedID, let annotation = self.pointAnnotations[selectedID] {
                map.selectAnnotation(annotation, animated: true)
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let annotation as PointAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.pointReuseID, for: annotation)
                if let marker = view as? MKMarkerAnnotationView {
                    marker.markerTintColor = UIColor(annotation.point.tint)
                    marker.glyphImage = UIImage(systemName: annotation.point.systemImage)
                    marker.titleVisibility = .adaptive
                    marker.subtitleVisibility = .hidden
                    marker.displayPriority = .required   // the view model already clusters
                    marker.clusteringIdentifier = nil
                    marker.animatesWhenAdded = true
                }
                return view
            case let annotation as ClusterAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.clusterReuseID, for: annotation)
                (view as? ClusterAnnotationView)?.configure(with: annotation.cluster)
                return view
            default:
                return nil   // the user's location: MapKit's blue dot
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? ClusterAnnotation {
                // A bubble zooms in instead of staying selected.
                mapView.deselectAnnotation(cluster, animated: false)
                let tapped = cluster.cluster
                Task { @MainActor in
                    self.parent.onClusterTap(tapped)
                }
                return
            }
            guard !self.isSyncingSelection, let point = annotation as? PointAnnotation else {
                return
            }
            let id = point.point.id
            Task { @MainActor in
                self.parent.selectedID = id
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            guard !self.isSyncingSelection, let point = annotation as? PointAnnotation else {
                return
            }
            let id = point.point.id
            Task { @MainActor in
                // Only if nothing else got selected in the meantime.
                if self.parent.selectedID == id {
                    self.parent.selectedID = nil
                }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            // Not during SwiftUI's view update: this can be called from inside updateUIView.
            Task { @MainActor in
                self.parent.onRegionChange(region)
            }
        }
    }
}

// MARK: - Annotations

/// A page or spot shown as its own marker.
final class PointAnnotation: NSObject, MKAnnotation {
    let point: MapPoint
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(point: MapPoint) {
        self.point = point
        self.coordinate = point.coordinate
        self.title = point.title
    }
}

/// A bubble standing for several points.
final class ClusterAnnotation: NSObject, MKAnnotation {
    let cluster: MapCluster
    let coordinate: CLLocationCoordinate2D

    init(cluster: MapCluster) {
        self.cluster = cluster
        self.coordinate = cluster.coordinate
    }

    /// Same grid cell, same points: the annotation can stay as it is.
    static func key(for cluster: MapCluster) -> String {
        "\(cluster.id)|\(cluster.count)|\(cluster.latitude)|\(cluster.longitude)"
    }
}

/// Draws a cluster with the SwiftUI ClusterBubble, so it looks the same as before.
final class ClusterAnnotationView: MKAnnotationView {
    private var host: UIHostingController<ClusterBubble>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        self.collisionMode = .circle
        self.displayPriority = .required
        self.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(with cluster: MapCluster) {
        let bubble = ClusterBubble(count: cluster.count, tint: cluster.representative.tint)
        if let host = self.host {
            host.rootView = bubble
        } else {
            let host = UIHostingController(rootView: bubble)
            host.view.backgroundColor = .clear
            host.sizingOptions = .intrinsicContentSize
            self.addSubview(host.view)
            self.host = host
        }
        guard let view = self.host?.view else {
            return
        }
        // Room for the bubble's halo and shadow.
        let size = view.sizeThatFits(CGSize(width: 120, height: 120))
        let side = max(size.width, size.height, 44)
        self.frame.size = CGSize(width: side, height: side)
        view.frame = self.bounds
        self.accessibilityLabel = String(localized: "\(cluster.count) places")
        self.isAccessibilityElement = true
    }
}
