//
//  PageViewModel.swift
//  HitchWiki
//
//  Loads one page from the database off the main thread and keeps the screen's state.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class PageViewModel {
    enum State {
        case loading
        case loaded(PageContent)
        case missing
    }

    let title: String
    private(set) var state: State = .loading
    /// Cards that are open, by card id.
    var expandedCards = Set<Int>()

    private let injectedDatabase: HitchwikiDatabase?
    /// Read at query time, so a database installed by DatabaseSync is used straight away.
    private var database: HitchwikiDatabase? { self.injectedDatabase ?? HitchwikiDatabase.shared }

    init(title: String, database: HitchwikiDatabase? = nil) {
        self.title = title
        self.injectedDatabase = database
    }

    var content: PageContent? {
        if case .loaded(let content) = self.state {
            return content
        }
        return nil
    }

    func load() async {
        guard case .loading = self.state else {
            return
        }
        let title = self.title
        let database = self.database
        let content = await Task.detached(priority: .userInitiated) {
            Self.makeContent(title: title, database: database)
        }.value

        guard let content else {
            withAnimation(Theme.spring) {
                self.state = .missing
            }
            return
        }
        // Open the first couple of sections; long pages stay easy to scan.
        self.expandedCards = Set(content.cards.prefix(2).map(\.id))
        withAnimation(Theme.spring) {
            self.state = .loaded(content)
        }
    }

    func isExpanded(_ card: SectionCard) -> Bool {
        self.expandedCards.contains(card.id)
    }

    func setExpanded(_ isExpanded: Bool, for card: SectionCard) {
        if isExpanded {
            self.expandedCards.insert(card.id)
        } else {
            self.expandedCards.remove(card.id)
        }
    }

    private nonisolated static func makeContent(title: String, database: HitchwikiDatabase?) -> PageContent? {
        guard let database, let record = try? database.page(titled: title) else {
            return nil
        }
        return PageContent(record: record) { target in
            try? database.resolveTitle(target)
        }
    }
}
