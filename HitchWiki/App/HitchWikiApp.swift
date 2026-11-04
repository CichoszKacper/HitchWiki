//
//  HitchWikiApp.swift
//  HitchWiki
//

import SwiftUI

@main
struct HitchWikiApp: App {
    @State private var sync = DatabaseSync()
    /// The animated continuation of the launch screen, shown once per launch.
    @State private var showsSplash = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView(isReadyForOnboarding: !self.showsSplash)
                if self.showsSplash {
                    SplashView {
                        self.showsSplash = false
                    }
                    .zIndex(1)
                }
            }
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
