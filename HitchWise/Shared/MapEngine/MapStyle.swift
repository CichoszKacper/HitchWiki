//
//  MapStyle.swift
//  HitchWise
//
//  The map's look, made for hitchhikers: motorways, their slip roads, main roads and petrol stations stand out;
//  shops, restaurants and other points of interest are left off. Built from OpenFreeMap's tiles (OpenMapTiles
//  layers), in a light and a dark version.
//
//  The style is written to a file once and loaded from there, so the map starts without a connection.
//  Offline, the map stops at the zoom the downloaded country files go to and enlarges those tiles beyond it.
//

import Foundation

enum MapStyle {
    /// OpenFreeMap's tiles go to zoom 14; closer than that MapLibre enlarges them.
    static let onlineMaxZoom = 14

    /// The credit the map's data needs. OpenStreetMap's and OpenMapTiles' are required; OpenFreeMap's is a thank-you.
    static let attribution = "© OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors"
    static let copyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!

    /// A style file for the given appearance. `offlineMaxZoom` limits the map's tiles to what the
    /// downloaded files have; nil while online.
    static func url(dark: Bool, offlineMaxZoom: Int?) -> URL {
        let maxZoom = offlineMaxZoom ?? self.onlineMaxZoom
        let name = "map-style-v1-\(dark ? "dark" : "light")-z\(maxZoom).json"
        let url = URL.cachesDirectory.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path),
           let data = try? JSONSerialization.data(withJSONObject: self.style(palette: dark ? .dark : .light, maxZoom: maxZoom)) {
            try? data.write(to: url, options: .atomic)
        }
        return url
    }

    // MARK: - Palette

    struct Palette {
        var background, water, waterLabel, wood, grass, ice, sand, residential, park, building: String
        var boundary, boundaryRegion: String
        var motorway, motorwayCasing, trunk, primary, secondary, minor, roadCasing, path, rail: String
        var fuel: String
        var label, labelHalo, labelMinor: String

        static let light = Palette(
            background: "#f4f1ea", water: "#a9d3f0", waterLabel: "#3a6f99", wood: "#d6e8c8", grass: "#e2efd4", ice: "#ffffff",
            sand: "#f2e8c9", residential: "#ebe6dc", park: "#d4ebc5", building: "#e0d9cc",
            boundary: "#8e7fa3", boundaryRegion: "#b8aec6",
            motorway: "#f08a3c", motorwayCasing: "#c0601c", trunk: "#f7b45c", primary: "#fcd88a", secondary: "#fff3c4",
            minor: "#ffffff", roadCasing: "#cbc4b6", path: "#b9ad99", rail: "#a8a29a",
            fuel: "#2b6fd6",
            label: "#2c2a28", labelHalo: "#ffffff", labelMinor: "#5d5850")

        static let dark = Palette(
            background: "#1b1d22", water: "#16304a", waterLabel: "#7ea6c8", wood: "#1f2a22", grass: "#212a20", ice: "#2a2d33",
            sand: "#2b2924", residential: "#22242a", park: "#1f2b21", building: "#2a2c33",
            boundary: "#8a7fa8", boundaryRegion: "#4f4a5e",
            motorway: "#e07b33", motorwayCasing: "#7a3d12", trunk: "#b9853f", primary: "#8c7550", secondary: "#5b5650",
            minor: "#3a3c43", roadCasing: "#121316", path: "#4d4a44", rail: "#55534f",
            fuel: "#5b9cff",
            label: "#e8e6e1", labelHalo: "#16171b", labelMinor: "#a9a59d")
    }

    // MARK: - Style

    private static let source = "openmaptiles"
    private static let regular = ["Noto Sans Regular"]
    private static let bold = ["Noto Sans Bold"]
    /// Names in Latin letters where the map has them, so hitchhikers can read signs' transliteration.
    private static let name: [Any] = ["coalesce", ["get", "name:latin"], ["get", "name"]]

    static func style(palette p: Palette, maxZoom: Int) -> [String: Any] {
        [
            "version": 8,
            "name": "HitchWise",
            "sources": [
                self.source: [
                    "type": "vector",
                    "tiles": [MapTileLoader.tileURLTemplate],
                    "minzoom": 0,
                    "maxzoom": maxZoom,
                    "attribution": self.attribution
                ]
            ],
            "glyphs": MapTileLoader.glyphsURLTemplate,
            "layers": self.baseLayers(p) + self.roadLayers(p) + self.labelLayers(p)
        ]
    }

    private static func fill(_ id: String, _ layer: String, filter: [Any]? = nil, color: String,
                             minzoom: Double = 0, opacity: Any = 1) -> [String: Any] {
        var result: [String: Any] = ["id": id, "type": "fill", "source": self.source, "source-layer": layer, "minzoom": minzoom,
                                     "paint": ["fill-color": color, "fill-opacity": opacity]]
        if let filter {
            result["filter"] = filter
        }
        return result
    }

    /// Width that grows with zoom: [zoom, width] pairs.
    private static func width(_ stops: [(Double, Double)]) -> [Any] {
        var expression: [Any] = ["interpolate", ["exponential", 1.5], ["zoom"]]
        for (zoom, width) in stops {
            expression += [zoom, width]
        }
        return expression
    }

    private static func line(_ id: String, _ layer: String, filter: [Any], color: String, width: [Any],
                             minzoom: Double = 0, dash: [Double]? = nil, opacity: Double = 1) -> [String: Any] {
        var paint: [String: Any] = ["line-color": color, "line-width": width, "line-opacity": opacity]
        if let dash {
            paint["line-dasharray"] = dash
        }
        return ["id": id, "type": "line", "source": self.source, "source-layer": layer, "minzoom": minzoom, "filter": filter,
                "layout": ["line-join": "round", "line-cap": "round"], "paint": paint]
    }

    private static func baseLayers(_ p: Palette) -> [[String: Any]] {
        [
            ["id": "background", "type": "background", "paint": ["background-color": p.background]],
            self.fill("landuse-residential", "landuse", filter: ["in", ["get", "class"], ["literal", ["residential", "suburb", "neighbourhood"]]],
                      color: p.residential, minzoom: 8),
            self.fill("landcover-wood", "landcover", filter: ["==", ["get", "class"], "wood"], color: p.wood, opacity: 0.8),
            self.fill("landcover-grass", "landcover", filter: ["in", ["get", "class"], ["literal", ["grass", "farmland"]]],
                      color: p.grass, opacity: 0.5),
            self.fill("landcover-ice", "landcover", filter: ["==", ["get", "class"], "ice"], color: p.ice),
            self.fill("landcover-sand", "landcover", filter: ["==", ["get", "class"], "sand"], color: p.sand),
            self.fill("park", "park", color: p.park, minzoom: 8, opacity: 0.7),
            self.fill("water", "water", filter: ["!=", ["get", "brunnel"], "tunnel"], color: p.water),
            self.line("waterway", "waterway", filter: ["in", ["get", "class"], ["literal", ["river", "canal"]]], color: p.water,
                      width: self.width([(8, 0.5), (14, 3), (18, 10)]), minzoom: 8),
            self.fill("building", "building", color: p.building, minzoom: 14),
            self.line("boundary-region", "boundary", filter: ["all", ["==", ["get", "admin_level"], 4], ["!=", ["get", "maritime"], 1]],
                      color: p.boundaryRegion, width: self.width([(4, 0.5), (10, 1.2)]), minzoom: 4, dash: [3, 2]),
            self.line("boundary-country", "boundary",
                      filter: ["all", ["==", ["get", "admin_level"], 2], ["!=", ["get", "maritime"], 1], ["!=", ["get", "disputed"], 1]],
                      color: p.boundary, width: self.width([(2, 0.8), (6, 1.5), (12, 3)]))
        ]
    }

    private static func roadLayers(_ p: Palette) -> [[String: Any]] {
        let notTunnel: [Any] = ["!=", ["get", "brunnel"], "tunnel"]
        func classes(_ names: [String]) -> [Any] {
            ["in", ["get", "class"], ["literal", names]]
        }
        let minor = classes(["minor", "service"])
        let secondary = classes(["secondary", "tertiary"])
        let primary = classes(["primary"])
        let trunk = classes(["trunk"])
        let motorway = classes(["motorway"])

        // Casings first, then fills, from small roads up, so bigger roads are drawn on top.
        return [
            self.line("rail", "transportation", filter: ["all", classes(["rail"]), notTunnel], color: p.rail,
                      width: self.width([(8, 0.5), (14, 1.5)]), minzoom: 8, dash: [3, 3]),
            self.line("path", "transportation", filter: ["all", classes(["path", "track"]), notTunnel], color: p.path,
                      width: self.width([(13, 0.5), (18, 2)]), minzoom: 13, dash: [2, 1.5]),

            self.line("minor-casing", "transportation", filter: minor, color: p.roadCasing,
                      width: self.width([(12, 1), (14, 4), (18, 18)]), minzoom: 12),
            self.line("secondary-casing", "transportation", filter: secondary, color: p.roadCasing,
                      width: self.width([(8, 1), (12, 3), (14, 6), (18, 24)]), minzoom: 8),
            self.line("primary-casing", "transportation", filter: primary, color: p.roadCasing,
                      width: self.width([(6, 1), (10, 3), (14, 8), (18, 28)]), minzoom: 6),
            self.line("trunk-casing", "transportation", filter: trunk, color: p.motorwayCasing,
                      width: self.width([(5, 1), (10, 3.5), (14, 9), (18, 30)]), minzoom: 5),
            self.line("motorway-casing", "transportation", filter: motorway, color: p.motorwayCasing,
                      width: self.width([(4, 1), (10, 4), (14, 10), (18, 32)]), minzoom: 4),

            self.line("minor", "transportation", filter: minor, color: p.minor,
                      width: self.width([(12, 0.5), (14, 2.5), (18, 15)]), minzoom: 12),
            self.line("secondary", "transportation", filter: secondary, color: p.secondary,
                      width: self.width([(8, 0.6), (12, 2), (14, 4.5), (18, 21)]), minzoom: 8),
            self.line("primary", "transportation", filter: primary, color: p.primary,
                      width: self.width([(6, 0.6), (10, 2), (14, 6), (18, 25)]), minzoom: 6),
            self.line("trunk", "transportation", filter: trunk, color: p.trunk,
                      width: self.width([(5, 0.7), (10, 2.5), (14, 7), (18, 27)]), minzoom: 5),
            self.line("motorway", "transportation", filter: motorway, color: p.motorway,
                      width: self.width([(4, 0.8), (10, 3), (14, 8), (18, 29)]), minzoom: 4),
            // Slip roads are where most motorway hitchhiking happens: drawn on top so junctions read clearly.
            self.line("motorway-ramp", "transportation", filter: ["all", motorway, ["==", ["get", "ramp"], 1]], color: p.motorway,
                      width: self.width([(10, 1.5), (14, 5), (18, 18)]), minzoom: 10)
        ]
    }

    private static func symbol(_ id: String, _ layer: String, filter: [Any], minzoom: Double, maxzoom: Double = 24,
                               layout: [String: Any], paint: [String: Any]) -> [String: Any] {
        ["id": id, "type": "symbol", "source": self.source, "source-layer": layer, "minzoom": minzoom, "maxzoom": maxzoom,
         "filter": filter, "layout": layout, "paint": paint]
    }

    private static func labelLayers(_ p: Palette) -> [[String: Any]] {
        let halo: [String: Any] = ["text-color": p.label, "text-halo-color": p.labelHalo, "text-halo-width": 1.5]
        let minorHalo: [String: Any] = ["text-color": p.labelMinor, "text-halo-color": p.labelHalo, "text-halo-width": 1.2]
        func place(_ classes: [String]) -> [Any] {
            ["in", ["get", "class"], ["literal", classes]]
        }
        return [
            self.symbol("water-name", "water_name", filter: ["==", ["geometry-type"], "Point"], minzoom: 3,
                        layout: ["text-field": self.name, "text-font": self.regular, "text-size": 12, "text-max-width": 6],
                        paint: ["text-color": p.waterLabel, "text-halo-color": p.labelHalo, "text-halo-width": 1]),
            self.symbol("road-name", "transportation_name",
                        filter: ["in", ["get", "class"], ["literal", ["primary", "secondary", "tertiary", "minor"]]], minzoom: 13,
                        layout: ["symbol-placement": "line", "text-field": self.name, "text-font": self.regular,
                                 "text-size": ["interpolate", ["linear"], ["zoom"], 13, 10, 18, 14]],
                        paint: minorHalo),
            // Motorway and trunk numbers (A4, E40, M1): what hitchhikers write on their signs.
            self.symbol("road-ref", "transportation_name",
                        filter: ["all", ["in", ["get", "class"], ["literal", ["motorway", "trunk", "primary"]]], ["has", "ref"]], minzoom: 7,
                        layout: ["symbol-placement": "line", "symbol-spacing": 400, "text-field": ["get", "ref"],
                                 "text-font": self.bold, "text-size": 11, "text-rotation-alignment": "viewport",
                                 "text-padding": 20],
                        paint: ["text-color": "#ffffff", "text-halo-color": p.motorwayCasing, "text-halo-width": 3]),
            // Petrol stations: a dot and the brand or name.
            ["id": "fuel-dot", "type": "circle", "source": self.source, "source-layer": "poi", "minzoom": 12,
             "filter": ["==", ["get", "class"], "fuel"],
             "paint": ["circle-color": p.fuel, "circle-radius": ["interpolate", ["linear"], ["zoom"], 12, 3, 16, 6],
                       "circle-stroke-color": p.labelHalo, "circle-stroke-width": 1.5]],
            self.symbol("fuel-name", "poi", filter: ["==", ["get", "class"], "fuel"], minzoom: 14,
                        layout: ["text-field": self.name, "text-font": self.regular, "text-size": 11, "text-anchor": "top",
                                 "text-offset": [0, 0.7], "text-optional": true],
                        paint: ["text-color": p.fuel, "text-halo-color": p.labelHalo, "text-halo-width": 1.2]),
            self.symbol("place-village", "place", filter: place(["village", "hamlet", "suburb"]), minzoom: 11,
                        layout: ["text-field": self.name, "text-font": self.regular, "text-size": 12, "text-max-width": 8],
                        paint: minorHalo),
            self.symbol("place-town", "place", filter: place(["town"]), minzoom: 7,
                        layout: ["text-field": self.name, "text-font": self.regular,
                                 "text-size": ["interpolate", ["linear"], ["zoom"], 7, 11, 14, 16], "text-max-width": 8],
                        paint: halo),
            self.symbol("place-city", "place", filter: place(["city"]), minzoom: 4,
                        layout: ["text-field": self.name, "text-font": self.bold,
                                 "text-size": ["interpolate", ["linear"], ["zoom"], 4, 11, 12, 20], "text-max-width": 8,
                                 "symbol-sort-key": ["get", "rank"]],
                        paint: halo),
            self.symbol("place-country", "place", filter: place(["country"]), minzoom: 2, maxzoom: 8,
                        layout: ["text-field": self.name, "text-font": self.bold,
                                 "text-size": ["interpolate", ["linear"], ["zoom"], 2, 11, 6, 16], "text-max-width": 7,
                                 "text-transform": "uppercase", "text-letter-spacing": 0.08],
                        paint: ["text-color": p.labelMinor, "text-halo-color": p.labelHalo, "text-halo-width": 1.5])
        ]
    }
}
