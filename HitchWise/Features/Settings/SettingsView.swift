//
//  SettingsView.swift
//  HitchWise
//
//  The Settings tab: the account (optional sign-in), the guide language (downloads it when needed), the app language
//  (iOS keeps it per app, so this opens the system page) and where the content comes from.
//

import SwiftUI

struct SettingsView: View {
    @Environment(DatabaseSync.self) private var sync
    @State private var switchingTo: AppLanguage?
    @State private var failedLanguage: AppLanguage?

    private var languages: LanguageManager { .shared }

    var body: some View {
        NavigationStack {
            List {
                AccountSection()

                Section {
                    ForEach(AppLanguage.allCases) { language in
                        self.guideRow(language)
                    }
                } header: {
                    Text("Guide language")
                } footer: {
                    Text("The English guide is the most complete. Other languages are downloaded when you pick them and then work offline.")
                }

                Section {
                    Button {
                        self.languages.openLanguageSettings()
                    } label: {
                        LabeledContent {
                            Text(self.languages.interfaceLanguage.nativeName)
                        } label: {
                            Label("App language", systemImage: "character.bubble.fill")
                                .foregroundStyle(.primary)
                        }
                    }
                } footer: {
                    Text("HitchWise follows your iPhone's language. To use another one just for this app, go to Settings › HitchWise › Language.")
                }

                Section("About") {
                    LabeledContent("Guides", value: self.articleCount)
                    LabeledContent("Guide data from", value: self.dataDate)
                    LabeledContent("Hitchhiking spots", value: self.spotCount)
                    Link(destination: self.sync.dataLanguage.wikiBaseURL) {
                        Label("Open Hitchwiki.org", systemImage: "safari.fill")
                    }
                    Text("The guide's content comes from Hitchwiki, written by hitchhikers and shared under the Creative Commons Attribution-ShareAlike licence.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Hitchhiking spots, ratings and waiting times come from the Hitchhiking Rides Dataset by maps.hitchwiki.org, Hitchmap and their contributors, under the Open Database License (ODbL). Riders' comments are shared under CC BY-SA 4.0.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: RideSpotDetailsView.copyrightURL) {
                        Label("Data licence", systemImage: "doc.text.fill")
                    }
                    LabeledContent("Version", value: Self.appVersion)
                }
            }
            .navigationTitle("Settings")
            .alert("Couldn't download the guide", isPresented: self.showsFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your internet connection and try again.")
            }
        }
    }

    private func guideRow(_ language: AppLanguage) -> some View {
        Button {
            self.select(language)
        } label: {
            HStack(spacing: 14) {
                Text(language.flag)
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.nativeName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    GuideLanguageDescription(language: language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if self.switchingTo == language {
                    ProgressView()
                } else if self.languages.guideLanguage == language {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(.rect)
        }
        .disabled(self.switchingTo != nil)
        .accessibilityAddTraits(self.languages.guideLanguage == language ? .isSelected : [])
    }

    private func select(_ language: AppLanguage) {
        guard language != self.languages.guideLanguage else {
            return
        }
        self.switchingTo = language
        Task {
            let succeeded = await self.sync.switchGuide(to: language)
            self.switchingTo = nil
            if !succeeded {
                self.failedLanguage = language
            }
        }
    }

    private var showsFailure: Binding<Bool> {
        Binding(get: { self.failedLanguage != nil }, set: { if !$0 { self.failedLanguage = nil } })
    }

    private var articleCount: String {
        let count = HitchwikiDatabase.shared?.articleCount ?? 0
        return count > 0 ? count.formatted() : "–"
    }

    private var spotCount: String {
        // Read again when new data is installed.
        _ = self.sync.revision
        let count = SpotsDatabase.shared?.spotCount ?? 0
        return count > 0 ? count.formatted() : "–"
    }

    /// The data version is the time of the newest edit, YYYYMMDDHHMM in UTC.
    private var dataDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyyMMddHHmm"
        guard let date = parser.date(from: String(self.sync.dataVersion)) else {
            return "–"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(DatabaseSync())
        .environment(AuthManager.forPreviews())
}
