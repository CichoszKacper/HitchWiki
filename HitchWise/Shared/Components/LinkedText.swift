//
//  LinkedText.swift
//  HitchWiki
//
//  Plain text with tappable links, from the text + link ranges stored in the database.
//  Style it like any Text: LinkedText(...).font(.body)
//

import SwiftUI

struct LinkedText: View {
    let text: String
    let links: [PageLink]

    init(_ text: String, links: [PageLink] = []) {
        self.text = text
        self.links = links
    }

    var body: some View {
        Text(Self.attributed(self.text, links: self.links))
    }

    static func attributed(_ text: String, links: [PageLink]) -> AttributedString {
        var attributed = AttributedString(text)
        for link in links {
            // The database stores NSRange values (UTF-16 offsets), which this converts safely.
            guard let url = link.url, let range = Range(link.range, in: attributed) else {
                continue
            }
            attributed[range].link = url
        }
        return attributed
    }
}

#Preview {
    LinkedText("Kraków is a city in the south of Poland.",
               links: [PageLink(range: NSRange(location: 33, length: 6), destination: .page("Poland"))])
        .padding()
}
