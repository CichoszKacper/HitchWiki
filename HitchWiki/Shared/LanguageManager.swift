//
//  LanguageManager.swift
//  HitchWise
//
//  The two languages the app deals with:
//   • the interface language: follows iOS (Settings › HitchWise › Language), texts come from
//     Localizable.xcstrings;
//   • the guide language: which Hitchwiki database is used (English is bundled and the most
//     complete, Polish is downloaded). Chosen on first launch, changeable in Settings.
//

import SwiftUI
import Observation
import UIKit

/// A language HitchWise is available in, for the interface and for the guide.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english = "en"
    case polish = "pl"

    var id: String { self.rawValue }

    /// The language's own name: "English", "Polski".
    var nativeName: String {
        switch self {
        case .english: "English"
        case .polish: "Polski"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .polish: "🇵🇱"
        }
    }

    /// Hitchwiki on the web in this language, e.g. https://hitchwiki.org/pl/
    var wikiBaseURL: URL {
        URL(string: "https://hitchwiki.org/\(self.rawValue)/")!
    }

    /// The language the interface is shown in right now.
    static var interface: AppLanguage {
        Bundle.main.preferredLocalizations.first
            .flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? .english
    }
}

@MainActor
@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    nonisolated static let guideLanguageKey = "guideLanguage"

    /// The language of the Hitchwiki guide. Nil until the user picks one on first launch.
    private(set) var guideLanguage: AppLanguage?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.guideLanguage = Self.storedGuideLanguage(in: defaults)
    }

    /// True until the first-launch language choice has been made.
    var needsGuideLanguageChoice: Bool {
        self.guideLanguage == nil
    }

    var interfaceLanguage: AppLanguage {
        .interface
    }

    /// Remembers the guide language. DatabaseSync calls this once the data for it is ready.
    func setGuideLanguage(_ language: AppLanguage) {
        self.guideLanguage = language
        self.defaults.set(language.rawValue, forKey: Self.guideLanguageKey)
    }

    /// iOS keeps each app's interface language in Settings › HitchWise › Language: opens that page.
    func openLanguageSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// The stored guide language, readable from any thread (the database opens before the UI exists).
    nonisolated static func storedGuideLanguage(in defaults: UserDefaults = .standard) -> AppLanguage? {
        defaults.string(forKey: self.guideLanguageKey).flatMap(AppLanguage.init(rawValue:))
    }
}
