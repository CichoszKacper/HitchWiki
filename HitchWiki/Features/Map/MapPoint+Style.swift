//
//  MapPoint+Style.swift
//  HitchWiki
//
//  How each kind of point looks on the map and in lists.
//

import SwiftUI

extension MapPoint {
    private enum Category {
        case spot, serviceStation, country, region, place
    }

    private var category: Category {
        if self.kind == .spot {
            return .spot
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
        case .spot: return "hand.thumbsup.fill"
        case .serviceStation: return "fuelpump.fill"
        case .country: return "flag.fill"
        case .region: return "map.fill"
        case .place: return "building.2.fill"
        }
    }

    var tint: Color {
        switch self.category {
        case .spot: return .accentColor
        case .serviceStation: return .blue
        case .country: return .green
        case .region: return .teal
        case .place: return .indigo
        }
    }

    /// "Hitchhiking spot · Warsaw", "Service station", "Place"...
    var subtitle: String {
        switch self.category {
        case .spot: return String(localized: "Hitchhiking spot · \(self.pageTitle)", comment: "Map point subtitle; the page the spot is on")
        case .serviceStation: return String(localized: "Service station", comment: "Kind of page")
        case .country: return String(localized: "Country", comment: "Kind of page")
        case .region: return String(localized: "Region", comment: "Kind of page")
        case .place: return String(localized: "Place", comment: "Kind of page: a city, town or area")
        }
    }
}
