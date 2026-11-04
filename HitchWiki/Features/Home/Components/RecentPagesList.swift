//
//  RecentPagesList.swift
//  HitchWiki
//
//  "Recently viewed": the last pages the user opened, as rows in one card.
//  Long-press a row to remove it.
//

import SwiftUI

struct RecentPagesList: View {
    let pages: [RecentPage]
    /// The home screen's namespace, so a row zooms into its page.
    let transition: Namespace.ID
    var onRemove: (RecentPage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(self.pages.enumerated()), id: \.element.id) { index, page in
                let sourceID = "recent-\(page.title)"
                NavigationLink(value: PageRoute(title: page.title, sourceID: sourceID)) {
                    RecentPageRow(page: page)
                }
                .buttonStyle(HighlightRowButtonStyle())
                .matchedTransitionSource(id: sourceID, in: self.transition)
                .contextMenu {
                    Button("Remove from Recently Viewed", systemImage: "minus.circle", role: .destructive) {
                        self.onRemove(page)
                    }
                }

                if index < self.pages.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
        .clipShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .cardStyle()
    }
}

private struct RecentPageRow: View {
    let page: RecentPage

    var body: some View {
        HStack(spacing: 14) {
            let palette = AnimatedMeshBackground.palette(for: self.page.title)
            Image(systemName: self.page.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(LinearGradient(colors: [palette[0], palette[1]], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .rect(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(self.page.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = self.page.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(self.page.viewedAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

/// Greys the row while it is pressed, like a list row.
private struct HighlightRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.07) : Color.clear)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Shown under "Recently viewed" before any page has been opened.
struct RecentPagesEmptyCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing here yet")
                    .font(.headline)
                Text("Places you read about show up here, so you can jump straight back in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    @Previewable @Namespace var transition
    NavigationStack {
        VStack(spacing: 20) {
            RecentPagesList(pages: [
                RecentPage(title: "Kraków", subtitle: "Place · Poland", systemImage: "building.2.fill", viewedAt: .now.addingTimeInterval(-600)),
                RecentPage(title: "Poland", subtitle: "Country", systemImage: "globe.europe.africa.fill", viewedAt: .now.addingTimeInterval(-86_400))
            ], transition: transition) { _ in }
            RecentPagesEmptyCard()
        }
        .padding()
        .frame(maxHeight: .infinity)
        .background(Theme.background)
    }
}
