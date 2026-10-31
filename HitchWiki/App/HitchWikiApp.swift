//
//  HitchWikiApp.swift
//  HitchWiki
//

import SwiftUI

@main
struct HitchWikiApp: App {
    @State private var sync = DatabaseSync()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(self.sync)
                // Check for newer data on launch and whenever the app comes back (throttled in DatabaseSync).
                .onChange(of: self.scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        self.sync.syncIfNeeded()
                    }
                }
        }
    }
}
