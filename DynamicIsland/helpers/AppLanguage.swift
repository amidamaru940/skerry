/*
 * Skerry — a fork of Atoll (DynamicIsland)
 * Copyright (C) 2026 amidamaru940 and Skerry contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Foundation

/// The language of Skerry's interface, independent of the language of
/// macOS. Stored the way macOS does it for one app: `AppleLanguages` in the
/// app's own preferences, read when the app starts, so a change takes
/// effect after a restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    static let preferenceKey = "AppleLanguages"

    /// Each language is named in itself, so it can be found whatever the
    /// interface language is.
    var title: String {
        switch self {
        case .system: return String(localized: "As in System")
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    var languageCode: String? {
        self == .system ? nil : rawValue
    }

    /// The choice saved for this app. Only the app's own domain counts: the
    /// system language list also shows through `UserDefaults.standard`.
    static func current(in defaults: UserDefaults = .standard,
                        domain: String = Bundle.main.bundleIdentifier ?? "") -> AppLanguage {
        from(storedLanguages: defaults.persistentDomain(forName: domain)?[preferenceKey] as? [String])
    }

    /// Saves the choice; `.system` removes the override.
    static func apply(_ language: AppLanguage, to defaults: UserDefaults = .standard) {
        if let stored = storedLanguages(for: language) {
            defaults.set(stored, forKey: preferenceKey)
        } else {
            defaults.removeObject(forKey: preferenceKey)
        }
    }

    /// What `AppleLanguages` in the app's own preferences means.
    static func from(storedLanguages: [String]?) -> AppLanguage {
        guard let first = storedLanguages?.first else { return .system }
        if first.hasPrefix("ru") { return .russian }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// What goes into `AppleLanguages`; nil removes it.
    static func storedLanguages(for language: AppLanguage) -> [String]? {
        language.languageCode.map { [$0] }
    }
}

enum AppRelauncher {
    /// Starts a new copy of the running app and quits this one.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }
}
