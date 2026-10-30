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
            pieces.append(parts == 1 ? "1 part" : "\(parts) parts")
        }
        if self.spotCount > 0 {
            pieces.append(self.spotCount == 1 ? "1 spot" : "\(self.spotCount) spots")
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
        return URL(string: "https://hitchwiki.org/en/\(encoded)")
    }
}

// MARK: - Building

extension PageContent {
    /// Infobox fields shown as chips, in this order.
    private static let factStyles: [(field: String, label: String, systemImage: String)] = [
        ("country", "Country", "globe.europe.africa.fill"),
        ("state", "Region", "map.fill"),
        ("capital", "Capital", "building.columns.fill"),
        ("language", "Language", "character.bubble.fill"),
        ("pop", "Population", "person.3.fill"),
        ("currency", "Currency", "banknote.fill"),
        ("plate", "Plates", "car.fill"),
        ("motorways", "Motorways", "road.lanes"),
        ("expressways", "Expressways", "road.lanes")
    ]

    /// - Parameter resolve: turns a wiki link target into the title of a page we have, or nil.
    init(record: PageRecord, resolve: (String) -> String?) {
        self.record = record
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
            kind = "Country"
        case "servicestation"?:
            kind = "Service station"
        case "district"?:
            kind = "District"
        case let type? where type.contains("location"):
            kind = "Place"
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

    /// An icon that matches common Hitchwiki headings.
    static func symbol(forHeading heading: String) -> String {
        let heading = heading.lowercased()
        let rules: [(keywords: [String], symbol: String)] = [
            (["hitchhiking out", "getting out", "leaving"], "arrow.up.forward.circle.fill"),
            (["hitchhiking in", "getting in", "arriving", "into"], "arrow.down.forward.circle.fill"),
            (["legal", "law"], "checkmark.shield.fill"),
            (["safety", "danger", "warning"], "exclamationmark.shield.fill"),
            (["tip"], "lightbulb.fill"),
            (["camp", "sleep", "accommodation", "couch"], "tent.fill"),
            (["experience", "stories", "story"], "quote.bubble.fill"),
            (["border", "visa"], "signpost.right.fill"),
            (["public transport", "transport", "bus", "train", "metro"], "tram.fill"),
            (["food", "eat", "drink"], "fork.knife"),
            (["language", "phrase"], "character.bubble.fill"),
            (["motorway", "highway", "road", "autobahn"], "road.lanes"),
            (["map", "spot"], "mappin.and.ellipse"),
            (["history"], "clock.fill"),
            (["see also", "external", "links"], "link"),
            (["hitchhiking", "hitching"], "hand.thumbsup.fill")
        ]
        return rules.first { rule in rule.keywords.contains { heading.contains($0) } }?.symbol ?? "text.alignleft"
    }
}
