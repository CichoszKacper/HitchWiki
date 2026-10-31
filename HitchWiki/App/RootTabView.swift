//
//  RootTabView.swift
//  HitchWiki
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
            Tab(AppTab.profile.title, systemImage: AppTab.profile.systemImage, value: AppTab.profile) {
                PlaceholderTabView(tab: .profile)
            }
        }
        .tint(Color.accentColor)
        .sensoryFeedback(.selection, trigger: self.selection)
        // "Syncing Hitchwiki data…" while a new database downloads.
        .overlay(alignment: .top) {
            if self.sync.showsBanner {
                SyncBanner(phase: self.sync.phase)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(DatabaseSync())
}
