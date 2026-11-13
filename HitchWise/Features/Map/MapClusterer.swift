//
//  MapClusterer.swift
//  HitchWiki
//
//  Groups map points that would overlap on screen into clusters.
//
//  Points are dropped into a grid of square cells, 1-2x `cellSize` points wide on screen. The grid is
//  anchored to the map (Mercator map points, not the screen) and its size only changes in powers of two,
//  so clusters stay put while panning and only regroup when the zoom level really changes.
//

import Foundation
import MapKit

/// Several points close together, drawn as one bubble with a count.
struct MapCluster: Identifiable, Hashable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let count: Int
    /// A point of the most common kind in the cluster, for its colour and icon.
    let representative: MapPoint
    /// The area the cluster's points cover, to zoom into when tapped.
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: self.latitude, longitude: self.longitude)
    }

    /// A region showing all of the cluster's points with some room around them.
    var region: MKCoordinateRegion {
        // Points on (almost) the same spot: zoom in past the clustering threshold so they separate.
        // Only longitude gets the minimum; MapKit widens the other side to fit the screen.
        let latitudeDelta = max((self.maxLatitude - self.minLatitude) * 1.8, 0.0005)
        let longitudeDelta = max((self.maxLongitude - self.minLongitude) * 1.8, MapClusterer.unclusteredSpan * 0.5)
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (self.minLatitude + self.maxLatitude) / 2,
                                                                 longitude: (self.minLongitude + self.maxLongitude) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: min(latitudeDelta, 170),
                                                         longitudeDelta: min(longitudeDelta, 350)))
    }
}

enum MapClusterer {
    struct Result: Sendable {
        var singles: [MapPoint] = []
        var clusters: [MapCluster] = []
    }

    /// Zoomed in closer than this many degrees of longitude, every point is shown on its own.
    static let unclusteredSpan = 0.01
    /// Most single markers when not clustering (only happens zoomed right in).
    private static let singlesLimit = 500

    /// - Parameters:
    ///   - mapSize: the map's size on screen, in points.
    ///   - cellSize: markers closer than roughly this many points (up to twice it) merge into a cluster.
    ///   - keepingSeparate: a point that is never clustered and always included, e.g. the selected one.
    static func cluster(_ points: [MapPoint], in region: MKCoordinateRegion, mapSize: CGSize,
                        cellSize: Double = 64, keepingSeparate separateID: String? = nil) -> Result {
        let span = region.span
        let center = region.center

        // Grid cell: the map's width in degrees divided into powers of two, so it stays the same while
        // panning and for small zoom changes. floor() keeps cells between 1x and 2x `cellSize`.
        let width = max(Double(mapSize.width), 100)
        let wantedCellDegrees = max(span.longitudeDelta * cellSize / width, 1e-9)
        let zoom = max(0, Int(floor(log2(360 / wantedCellDegrees))))
        let cellDegrees = 360 / pow(2, Double(zoom))
        // Cells are squares on the (Mercator) map, measured in MapKit map points.
        let cellMapPoints = MKMapSize.world.width / pow(2, Double(zoom))

        // On screen plus at least one cell around it, so edge clusters don't change while panning.
        let latitudeMargin = span.latitudeDelta / 2 + cellDegrees
        let longitudeMargin = span.longitudeDelta / 2 + cellDegrees
        var result = Result()
        var visible = [MapPoint]()
        for point in points {
            if point.id == separateID {
                result.singles.append(point)
                continue
            }
            var longitudeDistance = abs(point.longitude - center.longitude)
            if longitudeDistance > 180 {
                longitudeDistance = 360 - longitudeDistance   // across the date line
            }
            if abs(point.latitude - center.latitude) <= latitudeMargin && longitudeDistance <= longitudeMargin {
                visible.append(point)
            }
        }

        if span.longitudeDelta < Self.unclusteredSpan {
            result.singles += visible.prefix(Self.singlesLimit)
            return result
        }

        struct Cell: Hashable {
            let x: Int
            let y: Int
        }
        var cells = [Cell: [MapPoint]]()
        for point in visible {
            // Clamp away from the poles, where Mercator y goes to infinity.
            let mapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: min(max(point.latitude, -85), 85), longitude: point.longitude))
            let cell = Cell(x: Int(floor(mapPoint.x / cellMapPoints)), y: Int(floor(mapPoint.y / cellMapPoints)))
            cells[cell, default: []].append(point)
        }

        for (cell, members) in cells {
            guard members.count > 1, let first = members.first else {
                result.singles += members
                continue
            }
            var latitudeSum = 0.0, longitudeSum = 0.0
            var minLatitude = first.latitude, maxLatitude = first.latitude
            var minLongitude = first.longitude, maxLongitude = first.longitude
            var kinds = [String: (count: Int, point: MapPoint)]()
            for point in members {
                latitudeSum += point.latitude
                longitudeSum += point.longitude
                minLatitude = min(minLatitude, point.latitude)
                maxLatitude = max(maxLatitude, point.latitude)
                minLongitude = min(minLongitude, point.longitude)
                maxLongitude = max(maxLongitude, point.longitude)
                let kind = point.systemImage
                kinds[kind] = ((kinds[kind]?.count ?? 0) + 1, kinds[kind]?.point ?? point)
            }
            // Most common kind; ties broken by id so the colour doesn't flicker between regroupings.
            let representative = kinds.values.max { ($0.count, $0.point.id) < ($1.count, $1.point.id) }?.point ?? first
            let count = Double(members.count)
            result.clusters.append(MapCluster(id: "\(zoom)/\(cell.x)/\(cell.y)",
                                              latitude: latitudeSum / count, longitude: longitudeSum / count,
                                              count: members.count, representative: representative,
                                              minLatitude: minLatitude, maxLatitude: maxLatitude,
                                              minLongitude: minLongitude, maxLongitude: maxLongitude))
        }
        return result
    }
}
