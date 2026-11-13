//
//  MapAttribution.swift
//  HitchWise
//
//  The credit on the map for the data it shows: the spots (Hitchwiki, Hitchmap) and the base map
//  (OpenStreetMap through OpenMapTiles and OpenFreeMap). The ODbL asks for both on the map itself,
//  not behind a menu. Tapping a credit opens its licence page.
//

import SwiftUI

struct MapAttribution: View {
    /// Include the spots' credit (off on maps showing only the guide's own spots).
    var showsSpotsCredit = true

    var body: some View {
        HStack(spacing: 4) {
            if self.showsSpotsCredit {
                Link(destination: RideSpotDetailsView.copyrightURL) {
                    Text("Spots © Hitchwiki & Hitchmap", comment: "Credit shown on the map for the spots and guide data")
                }
                Text("·")
            }
            Link(destination: MapStyle.copyrightURL) {
                Text("Map © OpenStreetMap, OpenMapTiles, OpenFreeMap",
                     comment: "Credit shown on the map for the base map; keep the names as they are")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: .capsule)
        .padding(.horizontal, 8)
    }
}

#Preview {
    MapAttribution()
        .padding()
}
