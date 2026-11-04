//
//  RecentPages.swift
//  HitchWiki
//
//  The pages the user opened most recently, newest first, kept between launches.
//  PageView records a page once it has loaded; the home screen lists them.
//

import Foundation
import Observation

struct RecentPage: Codable, Hashable, Identifiable, Sendable {
    let title: String
    /// "Place · Poland"
    let subtitle: String?
    /// SF Symbol matching the kind of page (country, city, service station...).
    let systemImage: String
    let viewedAt: Date

    var id: String { self.title }
}

@MainActor
@Observable
final class RecentPages {
    static let shared = RecentPages()

    private(set) var pages: [RecentPage]

    private static let storageKey = "recentPages"
    private static let limit = 12
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let pages = try? JSONDecoder().decode([RecentPage].self, from: data) {
            self.pages = pages
        } else {
            self.pages = []
        }
    }

    /// Moves the page to the top of the list.
    func record(title: String, subtitle: String?, systemImage: String) {
        var pages = self.pages.filter { $0.title != title }
        pages.insert(RecentPage(title: title, subtitle: subtitle, systemImage: systemImage, viewedAt: .now), at: 0)
        self.pages = Array(pages.prefix(Self.limit))
        self.save()
    }

    func remove(_ page: RecentPage) {
        self.pages.removeAll { $0.title == page.title }
        self.save()
    }

    func removeAll() {
        self.pages = []
        self.save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(self.pages) {
            self.defaults.set(data, forKey: Self.storageKey)
        }
    }
}
