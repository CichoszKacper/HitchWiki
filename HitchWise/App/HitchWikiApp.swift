//
//  HitchWikiApp.swift
//  HitchWiki
//

import Firebase
import SwiftUI

@main
struct HitchWikiApp: App {
    @State private var sync = DatabaseSync()
    /// Optional sign-in with Google (Firebase). Created in init, after Firebase is configured.
    @State private var auth: AuthManager
    /// The animated continuation of the launch screen, shown once per launch.
    @State private var showsSplash = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        // Maps: route their requests through the offline files, and watch the connection.
        MapTileLoader.install()
        MapConnectivity.shared.start()
        OfflineMapStore.shared.start()
        self._auth = State(initialValue: AuthManager())
    }

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
            .environment(self.auth)
            // Google's sign-in sheet returns to the app through a URL.
            .onOpenURL { url in
                self.auth.handleOpenURL(url)
            }
            // Check for newer data on launch and whenever the app comes back (throttled in DatabaseSync).
            .onChange(of: self.scenePhase, initial: true) { _, phase in
                if phase == .active {
                    self.sync.syncIfNeeded()
                }
            }
        }
    }
}
