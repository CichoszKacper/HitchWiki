//
//  AppTab.swift
//  HitchWiki
//
//  The tabs in the bottom bar. Saved is a placeholder for now:
//  rename tabs / change their icons here.
//

import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case map
    case saved
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return String(localized: "Home", comment: "Tab bar")
        case .map: return String(localized: "Map", comment: "Tab bar")
        case .saved: return String(localized: "Saved", comment: "Tab bar")
        case .settings: return String(localized: "Settings", comment: "Tab bar")
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .map: return "map.fill"
        case .saved: return "bookmark.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
