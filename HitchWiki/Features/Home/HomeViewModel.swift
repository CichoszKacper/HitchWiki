//
//  HomeViewModel.swift
//  HitchWiki
//
//  Page list and title search for the home screen (same behaviour as the old UIKit main menu).
//

import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var query = ""
    private(set) var pages = [PageSummary]()
    private(set) var filteredPages = [PageSummary]()

    /// Titles containing any of these are hidden (carried over from the old main menu).
    let stringsToExclude = ["Main Page", "MediaWiki", "User", "Template", "Hitch", "Category", "Top", "Help", "phrasebook", "Talk",
                            "What to", "How to", "File:", "Encyclopedia", "Academy", "Sign Up", "Portal:", "Resources"]

    private let database: HitchwikiDatabase?

    init(database: HitchwikiDatabase? = HitchwikiDatabase.shared) {
        self.database = database
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

    private func excludingUnwantedTitles(_ pages: [PageSummary]) -> [PageSummary] {
        pages.filter { page in
            !self.stringsToExclude.contains { page.title.lowercased().contains($0.lowercased()) }
        }
    }
}
