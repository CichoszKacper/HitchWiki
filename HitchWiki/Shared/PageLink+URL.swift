//
//  PageLink+URL.swift
//  HitchWiki
//
//  Links to other Hitchwiki pages are put into text as an app-only URL (hitchwiki-page:Krak%C3%B3w)
//  so SwiftUI's Text makes them tappable; PageView's OpenURLAction turns them back into a page title.
//

import Foundation

extension PageLink {
    static let pageScheme = "hitchwiki-page"

    static func url(forPage title: String) -> URL? {
        var components = URLComponents()
        components.scheme = self.pageScheme
        components.path = title
        return components.url
    }

    /// The page title in a hitchwiki-page: URL, or nil for any other URL.
    static func pageTitle(from url: URL) -> String? {
        guard url.scheme == self.pageScheme else {
            return nil
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }

    /// Where tapping the link should go.
    var url: URL? {
        switch self.destination {
        case .page(let title):
            return Self.url(forPage: title)
        case .url(let url):
            return url
        }
    }
}

extension PageSpot {
    /// The heading the spot was written under, e.g. "Option 1, S8 onramp".
    var name: String {
        let name = self.sectionPath.components(separatedBy: " > ").last ?? ""
        return name.isEmpty ? "Hitchhiking spot" : name
    }
}
