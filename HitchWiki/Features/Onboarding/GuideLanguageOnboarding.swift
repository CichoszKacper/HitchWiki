//
//  GuideLanguageOnboarding.swift
//  HitchWise
//
//  First launch: welcome, and pick the language of the guide. English is bundled with the app
//  and is by far the most complete; Polish is smaller and downloaded on the spot.
//  RootTabView shows this until a guide language has been set.
//

import SwiftUI

struct GuideLanguageOnboarding: View {
    @Environment(DatabaseSync.self) private var sync
    @State private var selection: AppLanguage = .english
    @State private var manifests = [AppLanguage: DatabaseManifest]()
    @State private var downloadFailed = false

    private var isDownloading: Bool {
        self.sync.downloadingLanguage != nil
    }

    var body: some View {
        ZStack {
            AnimatedMeshBackground(seed: "HitchWise")
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    self.header
                    VStack(spacing: 12) {
                        ForEach(AppLanguage.allCases) { language in
                            self.option(language)
                        }
                    }
                    Text("You can change this anytime in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                self.footer
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            // Download size and article count of the guides that aren't on the phone yet.
            for language in AppLanguage.allCases where language != .english {
                if let manifest = await self.sync.manifest(for: language) {
                    self.manifests[language] = manifest
                }
            }
        }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .glassBackground(in: .circle)
                .accessibilityHidden(true)
            Text("Welcome to HitchWise")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Your offline hitchhiking guide: cities, spots and tips from the Hitchwiki community.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose the language of the guide")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func option(_ language: AppLanguage) -> some View {
        let isSelected = self.selection == language
        Button {
            withAnimation(Theme.spring) {
                self.selection = language
                self.downloadFailed = false
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(language.flag)
                    .font(.system(size: 36))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(language.nativeName)
                            .font(.title3.weight(.bold))
                        if language == .english {
                            Text("Most complete")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white, in: .capsule)
                        }
                    }
                    GuideLanguageDescription(language: language)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                    if let stats = self.stats(for: language) {
                        Text(stats)
                            .font(.subheadline.weight(.semibold))
                    }
                    self.availability(for: language)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(18)
            .glassBackground(in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.95 : 0.2), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .disabled(self.isDownloading)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "6489 guides · 902 spots"
    private func stats(for language: AppLanguage) -> String? {
        let counts: (articles: Int, spots: Int)?
        if language == .english, let database = HitchwikiDatabase.shared, database.language == .english, database.articleCount > 0 {
            counts = (database.articleCount, database.spotCount)
        } else if let stats = self.manifests[language]?.stats {
            counts = (stats.pages, stats.spots)
        } else {
            counts = nil
        }
        guard let counts else {
            return nil
        }
        return String(localized: "\(counts.articles) guides", comment: "Number of guide articles")
            + " · " + String(localized: "\(counts.spots) spots", comment: "Number of hitchhiking spots")
    }

    @ViewBuilder
    private func availability(for language: AppLanguage) -> some View {
        if language == .english {
            Label("Already on your phone, works offline right away", systemImage: "checkmark.seal.fill")
        } else if let size = self.manifests[language]?.database.compressedSize {
            Label("Downloads now (\(Int64(size).formatted(.byteCount(style: .file)))), then works offline",
                  systemImage: "arrow.down.circle.fill")
        } else {
            Label("Needs the internet once to download", systemImage: "arrow.down.circle.fill")
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if self.downloadFailed {
                Label("Couldn't download this guide. Check your connection and try again, or start with English.",
                      systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                self.choose(self.selection)
            } label: {
                HStack(spacing: 10) {
                    if self.isDownloading {
                        ProgressView()
                            .tint(.black)
                        Text("Downloading the guide…")
                    } else if self.downloadFailed {
                        Text("Try Again")
                    } else {
                        Text("Continue")
                    }
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: .capsule)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))
            .disabled(self.isDownloading)

            if self.downloadFailed {
                Button("Use English for now") {
                    withAnimation(Theme.spring) {
                        self.selection = .english
                    }
                    self.choose(.english)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(Theme.spring, value: self.downloadFailed)
        .animation(Theme.spring, value: self.isDownloading)
    }

    // MARK: - Actions

    /// Switches to `language` (downloading it if needed). On success LanguageManager gets a guide
    /// language and RootTabView closes this screen.
    private func choose(_ language: AppLanguage) {
        self.downloadFailed = false
        Task {
            let succeeded = await self.sync.switchGuide(to: language)
            if !succeeded {
                self.downloadFailed = true
            }
        }
    }
}

/// One line on what each guide is, shared by the first-launch screen and Settings.
struct GuideLanguageDescription: View {
    let language: AppLanguage

    var body: some View {
        switch self.language {
        case .english:
            Text("The biggest Hitchwiki, written by hitchhikers from all over the world.")
        case .polish:
            Text("A smaller guide written by the Polish community. Fewer places than in English.")
        }
    }
}

#Preview {
    GuideLanguageOnboarding()
        .environment(DatabaseSync())
}
