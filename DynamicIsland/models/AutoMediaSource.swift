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

import Defaults
import Foundation

/// A source the Auto music mode ranks. Spotify and Apple Music have their own
/// controllers, so they can be shown even when macOS reports another app as
/// now playing; every other app comes through the system Now Playing.
enum AutoMediaSource: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case spotify
    case appleMusic
    case otherApps

    var id: String { rawValue }

    /// Spotify → Apple Music → browsers and everything else.
    static let defaultOrder: [AutoMediaSource] = [.spotify, .appleMusic, .otherApps]

    static let spotifyBundleID = "com.spotify.client"
    static let appleMusicBundleID = "com.apple.Music"

    static func source(for bundleIdentifier: String) -> AutoMediaSource {
        switch bundleIdentifier {
        case spotifyBundleID: return .spotify
        case appleMusicBundleID: return .appleMusic
        default: return .otherApps
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .spotify: return Self.spotifyBundleID
        case .appleMusic: return Self.appleMusicBundleID
        case .otherApps: return nil
        }
    }

    var title: String {
        switch self {
        case .spotify: return String(localized: "Spotify")
        case .appleMusic: return String(localized: "Apple Music")
        case .otherApps: return String(localized: "Browsers and other apps")
        }
    }

    /// Browsers offered by "Ignore browsers" (only those installed are added).
    static let browserBundleIDs: [String] = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",       // Arc
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "ru.yandex.desktop.yandex-browser",
        "org.chromium.Chromium",
    ]
}

/// Which player the Auto mode shows.
enum AutoSourceChoice: Equatable {
    /// What macOS reports as now playing.
    case system
    /// Spotify or Apple Music through its own controller, while macOS
    /// reports another app (ignored or lower in the list).
    case dedicated(AutoMediaSource)
    /// Nothing to show: nothing plays, or only ignored apps.
    case none
}

enum AutoSourceResolver {
    static func normalizedOrder(_ stored: [AutoMediaSource]) -> [AutoMediaSource] {
        var seen = Set<AutoMediaSource>()
        var result = stored.filter { seen.insert($0).inserted }
        result += AutoMediaSource.defaultOrder.filter { !seen.contains($0) }
        return result
    }

    static func move(_ source: AutoMediaSource, onto target: AutoMediaSource, in order: [AutoMediaSource]) -> [AutoMediaSource] {
        var result = normalizedOrder(order)
        guard source != target, let from = result.firstIndex(of: source), let to = result.firstIndex(of: target) else { return result }
        result.remove(at: from)
        result.insert(source, at: to)
        return result
    }

    /// Among the players that are playing and not ignored, the one highest in
    /// `order` wins. When nothing plays, the app macOS reports stays shown
    /// (paused) unless it is ignored.
    ///
    /// - Parameters:
    ///   - systemApp: bundle identifier macOS reports as now playing.
    ///   - dedicatedPlaying: whether Spotify / Apple Music play, from their own controllers.
    static func choose(
        systemApp: String?,
        systemPlaying: Bool,
        dedicatedPlaying: [AutoMediaSource: Bool],
        order: [AutoMediaSource],
        ignored: Set<String>
    ) -> AutoSourceChoice {
        let order = normalizedOrder(order)
        let systemApp = systemApp.flatMap { $0.isEmpty ? nil : $0 }
        let systemAllowed = systemApp.map { !ignored.contains($0) } ?? false

        var candidates: [(source: AutoMediaSource, choice: AutoSourceChoice)] = []
        if let systemApp, systemPlaying, systemAllowed {
            candidates.append((AutoMediaSource.source(for: systemApp), .system))
        }
        for source in [AutoMediaSource.spotify, .appleMusic] {
            guard dedicatedPlaying[source] == true,
                  let bundleID = source.bundleIdentifier, !ignored.contains(bundleID),
                  !(systemApp == bundleID && systemPlaying) else { continue }
            candidates.append((source, .dedicated(source)))
        }

        func rank(_ source: AutoMediaSource) -> Int { order.firstIndex(of: source) ?? order.count }
        // Stable: on equal rank the system's own report comes first.
        if let best = candidates.enumerated().min(by: { lhs, rhs in
            (rank(lhs.element.source), lhs.offset) < (rank(rhs.element.source), rhs.offset)
        }) {
            return best.element.choice
        }
        return systemApp != nil && systemAllowed ? .system : .none
    }
}
