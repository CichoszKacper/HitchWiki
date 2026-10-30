//
//  AppTab.swift
//  HitchWiki
//
//  The tabs in the bottom bar. Everything except Home is a placeholder for now:
//  rename them / change their icons here.
//

import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case map
    case saved
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return "Home"
        case .map: return "Map"
        case .saved: return "Saved"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .map: return "map.fill"
        case .saved: return "bookmark.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}
