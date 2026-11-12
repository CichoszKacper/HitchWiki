//
//  RideSpotDetailsView.swift
//  HitchWise
//
//  What riders logged at a hitchhiking spot: its rating, the typical wait, how many rides, and their comments
//  (newest first, two shown until "Show all"). Ends with where the data comes from and its licence,
//  which the ODbL and CC BY-SA require.
//

import SwiftUI

struct RideSpotDetailsView: View {
    let details: RideSpotDetails

    @State private var showsAllComments = false

    private static let collapsedCommentCount = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if let rating = self.details.rating {
                        StatPill(systemImage: "star.fill", text: "\(rating.formatted(.number.precision(.fractionLength(1)))) · \(MapPoint.ratingLabel(rating))",
                                 tint: MapPoint.ratingColor(rating))
                            .accessibilityLabel(String(localized: "Rating \(rating.formatted(.number.precision(.fractionLength(1)))) of 5",
                                                       comment: "Accessibility: average rating of a hitchhiking spot"))
                    }
                    if let wait = self.details.waitMinutes {
                        StatPill(systemImage: "hourglass", text: Self.waitText(wait))
                            .accessibilityLabel(String(localized: "Typical wait \(Self.waitText(wait))",
                                                       comment: "Accessibility: median waiting time at a hitchhiking spot"))
                    }
                    StatPill(systemImage: "car.fill", text: MapPoint.ridesText(self.details.rides))
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

            if !self.details.comments.isEmpty {
                if self.showsAllComments {
                    ScrollView {
                        self.commentList(self.details.comments, lineLimit: nil)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    self.commentList(Array(self.details.comments.prefix(Self.collapsedCommentCount)), lineLimit: 3)
                }

                if self.canExpandComments {
                    Button(self.expandButtonTitle) {
                        withAnimation(Theme.spring) {
                            self.showsAllComments.toggle()
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }

            Link(destination: Self.copyrightURL) {
                Text(self.creditText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentList(_ comments: [SpotComment], lineLimit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(comments) { comment in
                CommentRow(comment: comment, lineLimit: lineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// More comments than are shown folded, or a shown one too long for its three lines.
    private var canExpandComments: Bool {
        self.details.comments.count > Self.collapsedCommentCount
            || self.details.comments.prefix(Self.collapsedCommentCount).contains { Self.isLong($0.text) }
    }

    private var expandButtonTitle: String {
        if self.showsAllComments {
            return String(localized: "Show less")
        }
        if self.details.comments.count > Self.collapsedCommentCount {
            return String(localized: "Show all \(self.details.comments.count) comments",
                          comment: "Expands the list of comments about a hitchhiking spot")
        }
        return String(localized: "Show more")
    }

    /// Likely cut off at three lines on a phone (~40 characters a line), like SpotDetailsView's fold.
    private static func isLong(_ text: String) -> Bool {
        text.count > 110 || text.filter(\.isNewline).count >= 3
    }

    /// "Rides from hitchmap.com, hitchwiki.org · ODbL, CC BY-SA 4.0"
    private var creditText: String {
        let licenses = self.details.licenses.map(Self.licenseName).joined(separator: ", ")
        return String(localized: "Rides from \(self.details.sources.joined(separator: ", ")) · \(licenses)",
                      comment: "Credit under a hitchhiking spot: the websites the rides were logged on, then their licences")
    }

    static let copyrightURL = URL(string: "https://maps.hitchwiki.org/copyright")!

    static func licenseName(_ code: String) -> String {
        switch code {
        case "odbl": return "ODbL"
        case "cc-by-sa-4.0": return "CC BY-SA 4.0"
        case "cc-by-4.0": return "CC BY 4.0"
        default: return code
        }
    }

    /// "25 min", "1 hr, 30 min" in the user's language.
    static func waitText(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// "2024-03" -> "Mar 2024" in the user's language.
    static func monthText(_ month: String) -> String? {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let monthNumber = Int(parts[1]) else {
            return nil
        }
        guard let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: monthNumber, day: 15)) else {
            return nil
        }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }
}

private struct StatPill: View {
    let systemImage: String
    let text: String
    /// Colours the icon and text; plain text colour when nil.
    var tint: Color?

    var body: some View {
        Label(self.text, systemImage: self.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(self.tint ?? Color.primary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: .capsule)
    }
}

private struct CommentRow: View {
    let comment: SpotComment
    let lineLimit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(self.comment.nickname ?? String(localized: "Anonymous", comment: "Author of a comment posted without a name"))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let rating = self.comment.rating {
                    Label(String(rating), systemImage: "star.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MapPoint.ratingColor(Double(rating)))
                        .fixedSize()
                        .accessibilityLabel(String(localized: "Rated \(rating) of 5", comment: "Accessibility: one rider's rating of a spot"))
                }
            }
            // On their own line, starting at the left, so a long name or a narrow card can't push them out of view.
            let month = self.comment.month.flatMap(RideSpotDetailsView.monthText)
            if month != nil || self.comment.waitMinutes != nil {
                HStack(spacing: 10) {
                    if let month {
                        Label(month, systemImage: "calendar")
                            .fixedSize()
                    }
                    if let wait = self.comment.waitMinutes {
                        Label(String(localized: "Waited \(RideSpotDetailsView.waitText(wait))",
                                     comment: "How long one rider waited at a hitchhiking spot"),
                              systemImage: "hourglass")
                            .fixedSize()
                    }
                }
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Text(self.comment.text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(self.lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    RideSpotDetailsView(details: RideSpotDetails(
        spotID: 1, rides: 37, rating: 4.3, waitMinutes: 17, waitCount: 15, lastRide: "2026-10",
        sources: ["hitchmap.com", "maps.hitchwiki.org"], licenses: ["cc-by-sa-4.0", "odbl"],
        comments: [
            SpotComment(id: 0, month: "2026-10", nickname: "Breno", rating: 5, waitMinutes: 10,
                        text: "Terrific spot. Found a great lift up to Ingolstadt.", source: "hitchmap.com", license: "odbl"),
            SpotComment(id: 1, month: "2026-09", nickname: nil, rating: 4, waitMinutes: 35,
                        text: "Stand after the traffic lights, cars are slow there and can stop in the bus bay.",
                        source: "maps.hitchwiki.org", license: "odbl"),
            SpotComment(id: 2, month: "2019-05", nickname: "anna", rating: 3, waitMinutes: nil,
                        text: "OK on weekdays.", source: "hitchwiki.org", license: "cc-by-sa-4.0"),
        ]))
        .padding()
}
