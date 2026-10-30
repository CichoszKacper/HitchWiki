//
//  HomeViewModel.swift
//  HitchWiki
//
//  Page list, title search and the places nearest to the user for the home screen.
//

import Foundation
import CoreLocation
import Observation

/// A city or area near the user.
struct NearbyPlace: Identifiable, Hashable {
    let page: PageSummary
    let distance: CLLocationDistance

    var id: Int64 { self.page.id }
}

@MainActor
@Observable
final class HomeViewModel {
    var query = ""
    private(set) var pages = [PageSummary]()
    private(set) var filteredPages = [PageSummary]()
    /// Closest cities/areas, nearest first.
    private(set) var nearby = [NearbyPlace]()

    /// Titles containing any of these are hidden (carried over from the old main menu).
    let stringsToExclude = ["Main Page", "MediaWiki", "User", "Template", "Hitch", "Category", "Top", "Help", "phrasebook", "Talk",
                            "What to", "How to", "File:", "Encyclopedia", "Academy", "Sign Up", "Portal:", "Resources"]

    private static let nearbyCount = 8

    @ObservationIgnored private let database: HitchwikiDatabase?
    @ObservationIgnored private var nearbyOrigin: CLLocation?
    @ObservationIgnored private var nearbyTask: Task<Void, Never>?

    init(database: HitchwikiDatabase? = HitchwikiDatabase.shared) {
        self.database = database
    }

    /// Nearby places matching the query (all of them for an empty query).
    var nearbyMatches: [NearbyPlace] {
        guard !self.query.isEmpty else {
            return self.nearby
        }
        return self.nearby.filter {
            $0.page.title.range(of: self.query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
    }

    /// Search results without the ones already listed under "Near you".
    var otherMatches: [PageSummary] {
        let nearbyIDs = Set(self.nearbyMatches.map(\.id))
        return self.filteredPages.filter { !nearbyIDs.contains($0.id) }
    }

    func loadData() {
        guard self.pages.isEmpty else {
            return
        }
        do {
            // The database only holds articles, so User:, Template: etc. are already gone.
            self.pages = self.excludingUnwantedTitles(try self.database?.allPages() ?? [])
            self.search()
        } catch {
            print("\(error)")
        }
    }

    /// Pages whose title starts with the query; all pages for an empty query.
    func search() {
        guard !self.query.isEmpty else {
            self.filteredPages = self.pages
            return
        }
        do {
            self.filteredPages = self.excludingUnwantedTitles(try self.database?.pages(titleStartingWith: self.query) ?? [])
        } catch {
            print("\(error)")
        }
    }

    /// Finds the closest cities/areas; skips the work unless the user moved more than a kilometre.
    func updateNearby(from location: CLLocation) {
        if let origin = self.nearbyOrigin, origin.distance(from: location) < 1_000 {
            return
        }
        self.nearbyOrigin = location
        let database = self.database
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        self.nearbyTask?.cancel()
        self.nearbyTask = Task {
            // Fetch extra: some results are roads, which get filtered out below.
            let points = await Task.detached(priority: .utility) {
                (try? database?.nearestPlaces(latitude: latitude, longitude: longitude, limit: 40)) ?? []
            }.value
            guard !Task.isCancelled else {
                return
            }
            let places = points
                .filter { !Self.isRoad($0.title) }
                .map { NearbyPlace(page: PageSummary(id: $0.rowID, title: $0.title),
                                   distance: location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
                .sorted { $0.distance < $1.distance }
            let kept = Set(self.excludingUnwantedTitles(places.map(\.page)).map(\.id))
            self.nearby = Array(places.filter { kept.contains($0.id) }.prefix(Self.nearbyCount))
        }
    }

    /// Road articles ("M25 (GB)", "A-5 (Spain)", "S1 (Poland)") have coordinates too, but aren't places.
    private static func isRoad(_ title: String) -> Bool {
        title.range(of: "^[A-Z]{1,3}-?[0-9]+[A-Z]?( \\(.+\\))?$", options: .regularExpression) != nil
    }

    private func excludingUnwantedTitles(_ pages: [PageSummary]) -> [PageSummary] {
        pages.filter { page in
            !self.stringsToExclude.contains { page.title.lowercased().contains($0.lowercased()) }
        }
    }
}
