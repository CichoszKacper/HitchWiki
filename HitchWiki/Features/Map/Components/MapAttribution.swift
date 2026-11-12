//
//  MapAttribution.swift
//  HitchWise
//
//  The credit on the map for the data it shows. The ODbL asks for it on the map itself,
//  not behind a menu (https://maps.hitchwiki.org/copyright). Tapping it opens that page.
//

import SwiftUI

struct MapAttribution: View {
    var body: some View {
        Link(destination: RideSpotDetailsView.copyrightURL) {
            Text("Data © Hitchwiki & Hitchmap contributors · ODbL, CC BY-SA",
                 comment: "Credit shown on the map for the spots and guide data")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassBackground(in: .capsule)
        }
    }
}

#Preview {
    MapAttribution()
        .padding()
}
