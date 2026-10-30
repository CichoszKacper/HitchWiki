//
//  Router.swift
//  HitchWiki
//
//  Navigation state for one tab's NavigationStack. Put it in the environment
//  so any view in the stack (e.g. a link in a page's text) can open another page.
//

import SwiftUI
import Observation

/// Opens a Hitchwiki page.
struct PageRoute: Hashable {
    let title: String
    /// Zoom from the row that was tapped (only rows in the home list are zoom sources).
    var zoomsFromSource = false
}

@MainActor
@Observable
final class Router {
    var path = NavigationPath()

    func open(page title: String) {
        self.path.append(PageRoute(title: title))
    }

    func popToRoot() {
        self.path = NavigationPath()
    }
}

extension View {
    /// Links in Text below this view: Hitchwiki pages open in `router`'s stack, websites in Safari.
    /// - Parameter beforeOpeningPage: e.g. dismiss a sheet first.
    func opensPageLinks(with router: Router, beforeOpeningPage: (() -> Void)? = nil) -> some View {
        self.environment(\.openURL, OpenURLAction { url in
            guard let title = PageLink.pageTitle(from: url) else {
                return .systemAction
            }
            beforeOpeningPage?()
            router.open(page: title)
            return .handled
        })
    }
}
