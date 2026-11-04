//
//  HomeViewModel.swift
//  HitchWiki
//
//  Everything on the home screen that comes from the database: the page list and title search,
//  the places nearest to the user, and the country they're in.
//

import Foundation
import CoreLocation
import Observation

/// A city or area near the user.
struct NearbyPlace: Identifiable, Hashable {
    let page: PageSummary
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    /// Region, country and spot count; nil if the lookup failed.
    let summary: PlaceSummary?

    var id: Int64 { self.page.id }

    static func == (lhs: NearbyPlace, rhs: NearbyPlace) -> Bool {
        lhs.page == rhs.page && lhs.distance == rhs.distance && lhs.summary == rhs.summary
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.page)
    }

    /// "Lesser Poland (Voivodeship)", else "Poland".
    var detail: String? {
        self.summary?.region ?? self.summary?.country
    }
}

@MainActor
@Observable
final class HomeViewModel {
    var query = ""
    private(set) var pages = [PageSummary]()
    private(set) var filteredPages = [PageSummary]()
    /// Closest cities/areas, nearest first.
    private(set) var nearby = [NearbyPlace]()
    /// The country the user is in, worked out from the places around them.
    private(set) var country: CountryOverview?
    /// True once the nearby places have been looked up for a location (the list may still be empty).
    private(set) var hasLoadedNearby = false

    /// Titles containing any of these are hidden (carried over from the old main menu).
    nonisolated static let stringsToExclude = ["Main Page", "MediaWiki", "User", "Template", "Hitch", "Category", "Top", "Help",
                                               "phrasebook", "Talk", "What to", "How to", "File:", "Encyclopedia", "Academy",
                                               "Sign Up", "Portal:", "Resources"]

    private nonisolated static let nearbyCount = 8

    @ObservationIgnored private let injectedDatabase: HitchwikiDatabase?
    /// Read at query time, so a database installed by DatabaseSync is used straight away.
    private var database: HitchwikiDatabase? { self.injectedDatabase ?? HitchwikiDatabase.shared }
    @ObservationIgnored private var nearbyOrigin: CLLocation?
    @ObservationIgnored private var nearbyTask: Task<Void, Never>?

    init(database: HitchwikiDatabase? = nil) {
        self.injectedDatabase = database
    }

    /// New data was installed: reload the list and the nearby places.
    func reload(location: CLLocation?) {
        self.pages = []
        self.loadData()
        self.nearbyOrigin = nil
        if let location {
            self.updateNearby(from: location)
        }
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
            self.pages = Self.excludingUnwantedTitles(try self.database?.allPages() ?? [])
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
            self.filteredPages = Self.excludingUnwantedTitles(try self.database?.pages(titleStartingWith: self.query) ?? [])
        } catch {
            print("\(error)")
        }
    }

    /// Finds the closest cities/areas and the user's country; skips the work unless the user moved more than a kilometre.
    func updateNearby(from location: CLLocation) {
        if let origin = self.nearbyOrigin, origin.distance(from: location) < 1_000 {
            return
        }
        self.nearbyOrigin = location
        let database = self.database
        self.nearbyTask?.cancel()
        self.nearbyTask = Task {
            let result = await Task.detached(priority: .utility) {
                Self.lookUpSurroundings(of: location, in: database)
            }.value
            guard !Task.isCancelled else {
                return
            }
            self.nearby = result.places
            self.country = result.country
            self.hasLoadedNearby = true
        }
    }

    // MARK: - Lookups (off the main thread)

    private nonisolated static func lookUpSurroundings(of location: CLLocation,
                                                       in database: HitchwikiDatabase?) -> (places: [NearbyPlace], country: CountryOverview?) {
        guard let database else {
            return ([], nil)
        }
        // Fetch extra: some results are roads or hidden titles, which get filtered out below.
        let points = (try? database.nearestPlaces(latitude: location.coordinate.latitude,
                                                  longitude: location.coordinate.longitude, limit: 40)) ?? []
        let kept = points.filter { !self.isRoad($0.title) && !self.isUnwanted($0.title) }
        let summaries = (try? database.placeSummaries(ids: kept.map(\.rowID))) ?? [:]

        let places = kept
            .map { point in
                NearbyPlace(page: PageSummary(id: point.rowID, title: point.title), coordinate: point.coordinate,
                            distance: location.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)),
                            summary: summaries[point.rowID])
            }
            .sorted { $0.distance < $1.distance }

        return (Array(places.prefix(self.nearbyCount)), self.dominantCountry(around: places, in: database))
    }

    /// The country most of the closest places are in, the closest ones counting the most
    /// (so a town across a nearby border doesn't win on its own).
    private nonisolated static func dominantCountry(around places: [NearbyPlace], in database: HitchwikiDatabase) -> CountryOverview? {
        var votes = [String: Double]()
        for (rank, place) in places.prefix(6).enumerated() {
            if let country = place.summary?.country {
                votes[country, default: 0] += 1 / Double(rank + 1)
            }
        }
        for name in votes.sorted(by: { $0.value > $1.value }).map(\.key) {
            if let overview = try? database.countryOverview(named: name) {
                return overview
            }
        }
        return nil
    }

    /// Road articles ("M25 (GB)", "A-5 (Spain)", "S1 (Poland)") have coordinates too, but aren't places.
    private nonisolated static func isRoad(_ title: String) -> Bool {
        title.range(of: "^[A-Z]{1,3}-?[0-9]+[A-Z]?( \\(.+\\))?$", options: .regularExpression) != nil
    }

    private nonisolated static func isUnwanted(_ title: String) -> Bool {
        let title = title.lowercased()
        return self.stringsToExclude.contains { title.contains($0.lowercased()) }
    }

    private nonisolated static func excludingUnwantedTitles(_ pages: [PageSummary]) -> [PageSummary] {
        pages.filter { !self.isUnwanted($0.title) }
    }
}

// MARK: - Country display

extension CountryOverview {
    /// The flag emoji, from the two-letter code in the `hitch` field (England, Scotland and Wales have their own).
    var flag: String? {
        switch self.title {
        case "England": return "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        case "Scotland": return "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        case "Wales": return "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"
        default: break
        }
        guard var code = self.hitchField?.lowercased(), code.count == 2,
              code.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) else {
            return nil
        }
        if code == "uk" {
            code = "gb"
        }
        var flag = ""
        for scalar in code.unicodeScalars {
            // Regional indicator symbols: 🇦 is U+1F1E6, "a" is 97.
            guard let indicator = Unicode.Scalar(0x1F1E6 + scalar.value - 97) else {
                return nil
            }
            flag.unicodeScalars.append(indicator)
        }
        return flag
    }

    /// "Very good", when the `hitch` field holds a rating rather than a country code.
    var hitchability: String? {
        guard let value = self.hitchField, value.count > 2 else {
            return nil
        }
        let cleaned = value
            .replacingOccurrences(of: "[{}<>.]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !cleaned.isEmpty, cleaned != "unknown", cleaned != "senseless" else {
            return nil
        }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    /// The first language listed: "English; recognized regional languages are..." -> "English".
    var mainLanguage: String? {
        self.language.flatMap(Self.firstItem)
    }

    /// "Pound sterling (GBP)" -> "Pound sterling".
    var shortCurrency: String? {
        guard let currency = self.currency.flatMap(Self.firstItem) else {
            return nil
        }
        let name = currency.components(separatedBy: " (").first ?? currency
        return name.isEmpty ? currency : name
    }

    private static func firstItem(_ value: String) -> String? {
        let first = value.components(separatedBy: CharacterSet(charactersIn: ";,/")).first?
            .trimmingCharacters(in: .whitespaces)
        return (first?.isEmpty ?? true) ? nil : first
    }
}
