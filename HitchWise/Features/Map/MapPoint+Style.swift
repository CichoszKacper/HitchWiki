//
//  MapPoint+Style.swift
//  HitchWiki
//
//  How each kind of point looks on the map and in lists.
//

import SwiftUI

extension MapPoint {
    private enum Category {
        case spot, rideSpot, serviceStation, country, region, place
    }

    private var category: Category {
        switch self.kind {
        case .spot:
            return .spot
        case .rideSpot:
            return .rideSpot
        case .page:
            break
        }
        switch self.infoboxType?.lowercased() {
        case "servicestation"?:
            return .serviceStation
        case "country"?:
            return .country
        case "district"?, "region"?:
            return .region
        default:
            return .place
        }
    }

    var systemImage: String {
        switch self.category {
        case .spot, .rideSpot: return "hand.thumbsup.fill"
        case .serviceStation: return "fuelpump.fill"
        case .country: return "flag.fill"
        case .region: return "map.fill"
        case .place: return "building.2.fill"
        }
    }

    /// Ride spots are coloured by their rating, like on Hitchmap.
    var tint: Color {
        switch self.category {
        case .spot: return .accentColor
        case .rideSpot: return Self.ratingColor(self.rating)
        case .serviceStation: return .blue
        case .country: return .green
        case .region: return .teal
        case .place: return .indigo
        }
    }

    /// Colour of a cluster bubble whose most common kind is this point's: one colour for all spots,
    /// so bubbles don't change colour with the rating of whichever spot came first.
    var clusterTint: Color {
        self.category == .rideSpot ? .accentColor : self.tint
    }

    /// "Hitchhiking spot · Warsaw", "12 rides", "Service station", "Place"...
    var subtitle: String {
        switch self.category {
        case .spot: return String(localized: "Hitchhiking spot · \(self.pageTitle)", comment: "Map point subtitle; the page the spot is on")
        case .rideSpot: return Self.ridesText(self.rideCount)
        case .serviceStation: return String(localized: "Service station", comment: "Kind of page")
        case .country: return String(localized: "Country", comment: "Kind of page")
        case .region: return String(localized: "Region", comment: "Kind of page")
        case .place: return String(localized: "Place", comment: "Kind of page: a city, town or area")
        }
    }

    /// "1 ride", "12 rides".
    static func ridesText(_ count: Int) -> String {
        String(localized: "\(count) rides", comment: "Number of rides logged at a hitchhiking spot")
    }

    /// Green for very good spots through yellow to red for senseless ones; grey when unrated.
    static func ratingColor(_ rating: Double?) -> Color {
        guard let rating else {
            return .gray
        }
        switch rating {
        case 4.5...: return Color(red: 0.13, green: 0.62, blue: 0.29)
        case 3.5..<4.5: return Color(red: 0.45, green: 0.75, blue: 0.22)
        case 2.5..<3.5: return Color(red: 0.93, green: 0.71, blue: 0.10)
        default: return Color(red: 0.84, green: 0.20, blue: 0.20)
        }
    }

    /// Hitchmap's words for a rating: "Very good", "Good", "Average", "Bad", "Senseless".
    static func ratingLabel(_ rating: Double) -> String {
        switch Int(rating.rounded()) {
        case 5...: return String(localized: "Very good", comment: "Rating of a hitchhiking spot, 5 of 5")
        case 4: return String(localized: "Good", comment: "Rating of a hitchhiking spot, 4 of 5")
        case 3: return String(localized: "Average", comment: "Rating of a hitchhiking spot, 3 of 5")
        case 2: return String(localized: "Bad", comment: "Rating of a hitchhiking spot, 2 of 5")
        default: return String(localized: "Senseless", comment: "Rating of a hitchhiking spot, 1 of 5")
        }
    }
}
