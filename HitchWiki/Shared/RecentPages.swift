//
//  RecentPages.swift
//  HitchWiki
//
//  The pages the user opened most recently, newest first, kept between launches.
//  PageView records a page once it has loaded; the home screen lists the ones from the
//  guide language in use (a Polish page title means nothing in the English database).
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
    /// Guide language of the page; nil for entries saved before languages existed (English).
    var language: AppLanguage? = nil

    var id: String { "\((self.language ?? .english).rawValue)/\(self.title)" }
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

    /// The pages from the `language` guide, newest first.
    func pages(in language: AppLanguage) -> [RecentPage] {
        self.pages.filter { ($0.language ?? .english) == language }
    }

    /// Moves the page to the top of the list.
    func record(title: String, subtitle: String?, systemImage: String, language: AppLanguage) {
        let page = RecentPage(title: title, subtitle: subtitle, systemImage: systemImage, viewedAt: .now, language: language)
        var pages = self.pages.filter { $0.id != page.id }
        pages.insert(page, at: 0)
        self.pages = Array(pages.prefix(Self.limit))
        self.save()
    }

    func remove(_ page: RecentPage) {
        self.pages.removeAll { $0.id == page.id }
        self.save()
    }

    /// Clears the list for one guide language.
    func removeAll(in language: AppLanguage) {
        self.pages.removeAll { ($0.language ?? .english) == language }
        self.save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(self.pages) {
            self.defaults.set(data, forKey: Self.storageKey)
        }
    }
}
