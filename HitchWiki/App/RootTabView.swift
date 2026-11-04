//
//  RootTabView.swift
//  HitchWise
//

import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .home
    /// Goes up every time the Home tab is tapped, also when it's already selected.
    @State private var homeTabTaps = 0
    @Environment(DatabaseSync.self) private var sync

    var body: some View {
        TabView(selection: self.tabSelection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                HomeView(returnToStartTrigger: self.homeTabTaps)
            }
            Tab(AppTab.map.title, systemImage: AppTab.map.systemImage, value: AppTab.map) {
                MapTabView()
            }
            Tab(AppTab.saved.title, systemImage: AppTab.saved.systemImage, value: AppTab.saved) {
                PlaceholderTabView(tab: .saved)
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(Color.accentColor)
        .sensoryFeedback(.selection, trigger: self.selection)
        // "Updating the guide…" while a new database downloads.
        .overlay(alignment: .top) {
            if self.sync.showsBanner {
                SyncBanner(phase: self.sync.phase)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // First launch: pick the guide language (English bundled, Polish downloaded).
        // Read here in body so the screen closes as soon as LanguageManager gets a guide language.
        .fullScreenCover(isPresented: .constant(LanguageManager.shared.needsGuideLanguageChoice)) {
            GuideLanguageOnboarding()
                .environment(self.sync)
                .interactiveDismissDisabled()
        }
    }
}

extension RootTabView {
    /// TabView sets the selection on every tap, even on the tab that's already showing,
    /// which is how a tap on Home can take the home screen back to its start.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { self.selection },
            set: { tab in
                if tab == .home {
                    self.homeTabTaps += 1
                }
                self.selection = tab
            }
        )
    }
}

#Preview {
    RootTabView()
        .environment(DatabaseSync())
}
