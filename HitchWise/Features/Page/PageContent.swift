//
//  PageContent.swift
//  HitchWiki
//
//  A PageRecord from the database, arranged for the page screen:
//  facts for the infobox, the intro, and the sections grouped into cards.
//

import Foundation
import MapKit

/// One infobox value shown as a chip.
struct Fact: Identifiable, Hashable, Sendable {
    /// The infobox field name, e.g. "capital".
    let id: String
    let label: String
    let value: String
    let systemImage: String
    /// Page to open when the chip is tapped.
    let linkedPage: String?
}

/// A top-level section and everything nested under it.
struct SectionCard: Identifiable, Hashable, Sendable {
    var id: Int { self.heading.id }
    let heading: PageSection
    /// Deeper headings under this one, in page order.
    let subsections: [PageSection]
    let systemImage: String
    let spotCount: Int

    /// "6 parts · 13 spots"
    var summary: String? {
        let parts = self.subsections.filter { $0.level == self.heading.level + 1 }.count
        var pieces = [String]()
        if parts > 0 {
            pieces.append(String(localized: "\(parts) parts", comment: "Number of subsections in a page section"))
        }
        if self.spotCount > 0 {
            pieces.append(String(localized: "\(self.spotCount) spots", comment: "Number of hitchhiking spots"))
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }
}

/// The map area shown in the header.
struct MapFrame: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double

    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: self.latitude, longitude: self.longitude),
                           span: MKCoordinateSpan(latitudeDelta: self.latitudeDelta, longitudeDelta: self.longitudeDelta))
    }

    /// Fits all `coordinates`, never zooming in closer than `minimumSpan` degrees.
    static func fitting(_ coordinates: [CLLocationCoordinate2D], minimumSpan: Double) -> MapFrame? {
        guard let first = coordinates.first else {
            return nil
        }
        var minLatitude = first.latitude, maxLatitude = first.latitude
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
        return MapFrame(latitude: (minLatitude + maxLatitude) / 2,
                        longitude: (minLongitude + maxLongitude) / 2,
                        latitudeDelta: min(max((maxLatitude - minLatitude) * 1.5, minimumSpan), 170),
                        longitudeDelta: min(max((maxLongitude - minLongitude) * 1.5, minimumSpan), 350))
    }
}

struct PageContent: Sendable {
    let record: PageRecord
    /// The Hitchwiki the page comes from.
    let language: AppLanguage
    /// "City · Poland"
    let subtitle: String?
    /// Shown on the header when there is no map.
    let headerSymbol: String
    let mapFrame: MapFrame?
    let facts: [Fact]
    let intro: PageSection?
    let cards: [SectionCard]
    /// Spots by the path of the section they are written in.
    let spotsByPath: [String: [PageSpot]]

    var title: String { self.record.title }

    func spots(in section: PageSection) -> [PageSpot] {
        self.spotsByPath[section.path] ?? []
    }

    /// Hitchwiki on the web, for sharing.
    var webURL: URL? {
        let path = self.title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: self.language.wikiBaseURL.absoluteString + encoded)
    }
}

// MARK: - Building

extension PageContent {
    /// Infobox fields shown as chips, in this order.
    private static var factStyles: [(field: String, label: String, systemImage: String)] {
        [
            ("country", String(localized: "Country", comment: "Infobox label"), "globe.europe.africa.fill"),
            ("state", String(localized: "Region", comment: "Infobox label"), "map.fill"),
            ("capital", String(localized: "Capital", comment: "Infobox label"), "building.columns.fill"),
            ("language", String(localized: "Language", comment: "Infobox label"), "character.bubble.fill"),
            ("pop", String(localized: "Population", comment: "Infobox label"), "person.3.fill"),
            ("currency", String(localized: "Currency", comment: "Infobox label"), "banknote.fill"),
            ("plate", String(localized: "Plates", comment: "Infobox label: car registration plates"), "car.fill"),
            ("motorways", String(localized: "Motorways", comment: "Infobox label"), "road.lanes"),
            ("expressways", String(localized: "Expressways", comment: "Infobox label"), "road.lanes")
        ]
    }

    /// - Parameters:
    ///   - language: the Hitchwiki the record comes from.
    ///   - resolve: turns a wiki link target into the title of a page we have, or nil.
    init(record: PageRecord, language: AppLanguage = .english, resolve: (String) -> String?) {
        self.record = record
        self.language = language
        self.subtitle = Self.subtitle(for: record)
        self.headerSymbol = Self.headerSymbol(for: record.infoboxType)

        // Facts
        var facts = [Fact]()
        for style in Self.factStyles {
            guard let field = record.infoboxFields.first(where: { $0.name.lowercased() == style.field }) else {
                continue
            }
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != "-" else {
                continue
            }
            // Only link a chip that names one page ("Warsaw"), not a list ("A2, A9, A10").
            let target: String? = field.links.count == 1 ? field.links[0] : (field.links.isEmpty ? value : nil)
            var linkedPage: String?
            if let target, let resolved = resolve(target), resolved != record.title {
                linkedPage = resolved
            }
            facts.append(Fact(id: style.field, label: style.label, value: value, systemImage: style.systemImage, linkedPage: linkedPage))
        }
        self.facts = facts

        // Spots
        let spotsByPath = Dictionary(grouping: record.spots, by: \.sectionPath)
        self.spotsByPath = spotsByPath

        // Map: fit the spots around the page's own position
        var coordinates = record.spots.map(\.coordinate)
        if let coordinate = record.coordinate {
            coordinates.append(coordinate)
        }
        let isCountry = record.infoboxType?.lowercased() == "country"
        self.mapFrame = MapFrame.fitting(coordinates, minimumSpan: isCountry ? 9 : 0.12)

        // Intro + cards
        let sections = record.sections.filter { !$0.title.isEmpty || !$0.text.isEmpty }
        self.intro = sections.first { $0.level == 0 && !$0.text.isEmpty }
        let headed = sections.filter { $0.level > 0 }
        let topLevel = headed.map(\.level).min() ?? 1

        var cards = [SectionCard]()
        var current: (heading: PageSection, subsections: [PageSection])?
        func closeCard() {
            guard let card = current else {
                return
            }
            let all = [card.heading] + card.subsections
            let spotCount = all.reduce(0) { $0 + (spotsByPath[$1.path]?.count ?? 0) }
            if !card.heading.text.isEmpty || !card.subsections.isEmpty {
                cards.append(SectionCard(heading: card.heading, subsections: card.subsections,
                                         systemImage: Self.symbol(forHeading: card.heading.title), spotCount: spotCount))
            }
            current = nil
        }
        for section in headed {
            if section.level <= topLevel || current == nil {
                closeCard()
                current = (section, [])
            } else {
                current?.subsections.append(section)
            }
        }
        closeCard()
        self.cards = cards
    }

    private static func subtitle(for record: PageRecord) -> String? {
        let kind: String?
        switch record.infoboxType?.lowercased() {
        case nil:
            kind = nil
        case "country"?:
            kind = String(localized: "Country", comment: "Kind of page")
        case "servicestation"?:
            kind = String(localized: "Service station", comment: "Kind of page")
        case "district"?:
            kind = String(localized: "District", comment: "Kind of page")
        case let type? where type.contains("location"):
            kind = String(localized: "Place", comment: "Kind of page: a city, town or area")
        case let type?:
            kind = type.capitalized
        }
        let country = record.country.flatMap { $0.isEmpty || $0 == "-" || $0 == record.title ? nil : $0 }
        let parts = [kind, country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func headerSymbol(for infoboxType: String?) -> String {
        switch infoboxType?.lowercased() {
        case "country"?:
            return "globe.europe.africa.fill"
        case "servicestation"?:
            return "fuelpump.fill"
        case let type? where type.contains("location") || type == "district":
            return "building.2.fill"
        default:
            return "hand.thumbsup.fill"
        }
    }

    /// An icon that matches common Hitchwiki headings (English and Polish wiki).
    static func symbol(forHeading heading: String) -> String {
        let heading = heading.lowercased()
        let rules: [(keywords: [String], symbol: String)] = [
            (["hitchhiking out", "getting out", "leaving", "wyjazd", "wydostać", "wylot"], "arrow.up.forward.circle.fill"),
            (["hitchhiking in", "getting in", "arriving", "into", "dojazd", "przyjazd", "wjazd"], "arrow.down.forward.circle.fill"),
            (["legal", "law", "legaln", "prawo", "przepis"], "checkmark.shield.fill"),
            (["safety", "danger", "warning", "bezpiecz", "niebezpie", "uwaga"], "exclamationmark.shield.fill"),
            (["tip", "porad", "wskazów", "rady"], "lightbulb.fill"),
            (["camp", "sleep", "accommodation", "couch", "nocleg", "spanie", "biwak"], "tent.fill"),
            (["experience", "stories", "story", "doświadcz", "relacj"], "quote.bubble.fill"),
            (["border", "visa", "granic", "wiza"], "signpost.right.fill"),
            (["public transport", "transport", "bus", "train", "metro", "autobus", "pociąg", "tramwaj", "komunikacja"], "tram.fill"),
            (["food", "eat", "drink", "jedzenie", "picie"], "fork.knife"),
            (["language", "phrase", "język", "rozmówki"], "character.bubble.fill"),
            (["motorway", "highway", "road", "autobahn", "autostrad", "drog"], "road.lanes"),
            (["map", "spot", "mapa", "miejsc"], "mappin.and.ellipse"),
            (["history", "histori"], "clock.fill"),
            (["see also", "external", "links", "zobacz też", "linki"], "link"),
            (["hitchhiking", "hitching", "autostop", "stop"], "hand.thumbsup.fill")
        ]
        return rules.first { rule in rule.keywords.contains { heading.contains($0) } }?.symbol ?? "text.alignleft"
    }
}
