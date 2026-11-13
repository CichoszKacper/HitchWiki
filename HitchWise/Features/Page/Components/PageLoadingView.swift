//
//  PageLoadingView.swift
//  HitchWiki
//
//  Shimmering placeholders in the shape of a page while it loads.
//

import SwiftUI

struct PageLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: PageHeroHeader.height)
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 130, height: 72)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<6, id: \.self) { line in
                        Capsule()
                            .fill(.quaternary)
                            .frame(height: 12)
                            .frame(maxWidth: line == 5 ? 180 : .infinity)
                    }
                }
                .padding(.horizontal, 20)
            }
            .shimmering()
        }
        .scrollDisabled(true)
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel("Loading page")
    }
}

#Preview {
    PageLoadingView()
}
