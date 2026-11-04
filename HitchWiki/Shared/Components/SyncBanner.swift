//
//  SyncBanner.swift
//  HitchWiki
//
//  A small capsule at the top of the screen while new guide data downloads.
//

import SwiftUI

struct SyncBanner: View {
    let phase: DatabaseSync.Phase

    var body: some View {
        HStack(spacing: 8) {
            switch self.phase {
            case .updated:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Guide updated")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Couldn't update, using saved data")
            default:
                ProgressView()
                    .controlSize(.small)
                Text("Updating the guide…")
            }
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .contentTransition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 12) {
        SyncBanner(phase: .syncing)
        SyncBanner(phase: .updated)
        SyncBanner(phase: .failed)
    }
    .padding()
}
