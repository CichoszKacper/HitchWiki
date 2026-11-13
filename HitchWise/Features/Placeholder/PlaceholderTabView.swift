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
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(self.tab.title)
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 6)
                ContentUnavailableView {
                    Label(self.tab.title, systemImage: self.tab.systemImage)
                        .symbolEffect(.breathe)
                } description: {
                    Text("Coming soon")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.background)
            .navigationTitle(self.tab.title)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    PlaceholderTabView(tab: .map)
}
