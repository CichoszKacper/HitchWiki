//
//  SpotDetailsView.swift
//  HitchWiki
//
//  Where a hitchhiking spot sits on its page ("Warsaw › Hitchhiking out › West towards Łódź")
//  and the wiki's directions for it, with tappable links. Long directions fold behind "Show more".
//

import SwiftUI

struct SpotDetailsView: View {
    let pageTitle: String
    /// Headings above the spot (not including the spot's own name).
    let headings: [String]
    let text: String
    var links: [PageLink] = []

    @State private var isExpanded = false

    private static let foldLength = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(([self.pageTitle] + self.headings).joined(separator: " › "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !self.text.isEmpty {
                if self.isExpanded {
                    ScrollView {
                        self.directions
                    }
                    .frame(maxHeight: 280)
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    self.directions
                        .lineLimit(5)
                }

                if self.text.count > Self.foldLength {
                    Button(self.isExpanded ? "Show less" : "Show more") {
                        withAnimation(Theme.spring) {
                            self.isExpanded.toggle()
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var directions: some View {
        LinkedText(self.text, links: self.links)
            .font(.callout)
            .foregroundStyle(.primary.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

#Preview {
    SpotDetailsView(pageTitle: "Warsaw", headings: ["Hitchhiking out", "West towards Łódź, Poznań, Berlin"],
                    text: "Take bus 103, 122, 180, 186 or 409 and get off at Gen. Maczka (Note: bus stops only on request here!). Hitch right from the bus stop where bus 186 in final direction Szczęśliwice stops. Holding a sign A2 makes the difference to get the ride out.")
        .padding()
}
