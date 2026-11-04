//
//  RootTabView.swift
//  HitchWise
//

import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .home
    @Environment(DatabaseSync.self) private var sync

    var body: some View {
        TabView(selection: self.$selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                HomeView()
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

#Preview {
    RootTabView()
        .environment(DatabaseSync())
}
