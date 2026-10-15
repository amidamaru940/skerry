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

/// A live indicator of the closed island whose place in the priority list the
/// user chooses. System HUDs (volume, brightness, battery, Caps Lock) are not
/// in the list: they stay above all of these.
enum ClosedIndicator: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case screenshot
    case colorPicked
    case clipboardPaused
    case music
    case timer
    case reminder
    case recording
    case download
    case localSend
    case focus
    case privacy
    case extensionActivity
    case shelf
    case keepAwake

    var id: String { rawValue }

    /// Screenshot → picked colour → clipboard pause → music → timer, then
    /// the rest in upstream's order; Keep Awake, which can stay on for
    /// hours, last. The two flashes answer something the user just did, so
    /// they come before music.
    static let defaultOrder: [ClosedIndicator] = [
        .screenshot, .colorPicked, .clipboardPaused, .music, .timer, .reminder, .recording,
        .download, .localSend, .focus, .privacy, .extensionActivity, .shelf, .keepAwake,
    ]

    /// Whether the indicator can ride along with music as the small badge on
    /// the artwork. Such indicators never push music off the island; the one
    /// highest in the list gets the badge.
    var pairsWithMusic: Bool {
        switch self {
        case .clipboardPaused, .timer, .reminder, .recording, .focus, .extensionActivity, .shelf, .keepAwake:
            return true
        case .screenshot, .colorPicked, .music, .download, .localSend, .privacy:
            return false
        }
    }

    var title: String {
        switch self {
        case .screenshot: return String(localized: "New screenshot")
        case .colorPicked: return String(localized: "Picked color")
        case .clipboardPaused: return String(localized: "Clipboard paused")
        case .music: return String(localized: "Music")
        case .timer: return String(localized: "Timer")
        case .reminder: return String(localized: "Reminder")
        case .recording: return String(localized: "Screen recording")
        case .download: return String(localized: "Download")
        case .localSend: return String(localized: "LocalSend")
        case .focus: return String(localized: "Focus")
        case .privacy: return String(localized: "Camera and microphone")
        case .extensionActivity: return String(localized: "Extensions")
        case .shelf: return String(localized: "Shelf")
        case .keepAwake: return String(localized: "Keep Awake")
        }
    }

    var icon: String {
        switch self {
        case .screenshot: return "camera.viewfinder"
        case .colorPicked: return "eyedropper"
        case .clipboardPaused: return "pause.circle"
        case .music: return "music.note"
        case .timer: return "timer"
        case .reminder: return "clock"
        case .recording: return "record.circle"
        case .download: return "arrow.down.circle"
        case .localSend: return "paperplane"
        case .focus: return "moon"
        case .privacy: return "video"
        case .extensionActivity: return "puzzlepiece.extension"
        case .shelf: return "tray.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        }
    }
}

/// What music shows on the closed island.
enum ClosedMusicStyle: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case artworkAndVisualizer
    case artworkOnly
    case visualizerOnly
    case scrollingTitle
    case nothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artworkAndVisualizer: return String(localized: "Artwork and visualizer")
        case .artworkOnly: return String(localized: "Artwork only")
        case .visualizerOnly: return String(localized: "Visualizer only")
        case .scrollingTitle: return String(localized: "Scrolling title")
        case .nothing: return String(localized: "Nothing")
        }
    }

    var showsArtwork: Bool { self == .artworkAndVisualizer || self == .artworkOnly || self == .scrollingTitle }
    var showsVisualizer: Bool { self == .artworkAndVisualizer || self == .visualizerOnly }
    var showsMusic: Bool { self != .nothing }

    /// Whether the closed island shows music at all: upstream's media
    /// controls setting and this style.
    static func closedMusicContentEnabled(standardMediaControls: Bool, style: ClosedMusicStyle) -> Bool {
        standardMediaControls && style.showsMusic
    }
}

/// Picks what the closed island shows when several indicators are active.
enum ClosedIndicatorResolver {
    /// The saved order with duplicates removed and indicators added since appended.
    static func normalizedOrder(_ stored: [ClosedIndicator]) -> [ClosedIndicator] {
        var seen = Set<ClosedIndicator>()
        var result = stored.filter { seen.insert($0).inserted }
        result += ClosedIndicator.defaultOrder.filter { !seen.contains($0) }
        return result
    }

    /// The indicator that gets the closed island: the first active one in
    /// `order`. While music is active, indicators that pair with music are
    /// shown as its badge instead and do not compete.
    static func winner(active: Set<ClosedIndicator>, order: [ClosedIndicator]) -> ClosedIndicator? {
        let musicActive = active.contains(.music)
        return normalizedOrder(order).first { indicator in
            active.contains(indicator) && !(musicActive && indicator.pairsWithMusic)
        }
    }

    /// The badge next to the music artwork: the first active indicator in
    /// `order` that pairs with music.
    static func musicBadge(active: Set<ClosedIndicator>, order: [ClosedIndicator]) -> ClosedIndicator? {
        firstMusicBadge(order: order) { active.contains($0) ? $0 : nil }
    }

    /// Walks the indicators that pair with music in `order` and returns the
    /// first badge `badge` makes, so only the needed state is looked up.
    static func firstMusicBadge<Badge>(order: [ClosedIndicator], _ badge: (ClosedIndicator) -> Badge?) -> Badge? {
        for indicator in normalizedOrder(order) where indicator.pairsWithMusic {
            if let made = badge(indicator) { return made }
        }
        return nil
    }

    /// Moves `indicator` to the position of `target` (dropping a row onto another).
    static func move(_ indicator: ClosedIndicator, onto target: ClosedIndicator, in order: [ClosedIndicator]) -> [ClosedIndicator] {
        var result = normalizedOrder(order)
        guard indicator != target, let from = result.firstIndex(of: indicator), let to = result.firstIndex(of: target) else { return result }
        result.remove(at: from)
        result.insert(indicator, at: to)
        return result
    }
}
