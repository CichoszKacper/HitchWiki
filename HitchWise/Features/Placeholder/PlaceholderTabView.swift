//
//  PlaceholderTabView.swift
//  HitchWiki
//
//  Temporary screen for tabs that don't do anything yet.
//

import SwiftUI

struct PlaceholderTabView: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(self.tab.title, systemImage: self.tab.systemImage)
                    .symbolEffect(.breathe)
            } description: {
                Text("Coming soon")
            }
            .background(Theme.background)
            .navigationTitle(self.tab.title)
        }
    }
}

#Preview {
    PlaceholderTabView(tab: .map)
}
