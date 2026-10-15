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

/// A tab of the expanded island that the user can order and hide.
/// Extension tabs are added after these and are not part of the layout.
enum NotchTab: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case nowPlaying
    case screenshots
    case clipboard
    case shelf
    case timer
    case notes
    case stats
    case llmUsage
    case terminal

    var id: String { rawValue }

    /// Screenshots live in the Clipboard tab now; the case stays so saved
    /// layouts still read.
    var isMergedIntoClipboard: Bool { self == .screenshots }

    /// The tab that shows this one's content.
    var shownAs: NotchTab { isMergedIntoClipboard ? .clipboard : self }

    static let defaultOrder: [NotchTab] = [.nowPlaying, .screenshots, .clipboard, .shelf, .timer, .notes, .stats, .llmUsage, .terminal]

    var view: NotchViews {
        switch self {
        case .nowPlaying: return .home
        case .screenshots: return .screenshots
        case .clipboard: return .clipboard
        case .shelf: return .shelf
        case .timer: return .timer
        case .notes: return .notes
        case .stats: return .stats
        case .llmUsage: return .llmUsage
        case .terminal: return .terminal
        }
    }

    init?(view: NotchViews) {
        guard let tab = NotchTab.allCases.first(where: { $0.view == view }) else { return nil }
        self = tab
    }

    var title: String {
        switch self {
        case .nowPlaying: return String(localized: "Now Playing")
        case .screenshots: return String(localized: "Screenshots")
        case .clipboard: return String(localized: "Clipboard")
        case .shelf: return String(localized: "Shelf")
        case .timer: return String(localized: "Timer")
        case .notes: return String(localized: "Notes")
        case .stats: return String(localized: "Stats")
        case .llmUsage: return String(localized: "Usage")
        case .terminal: return String(localized: "Terminal")
        }
    }

    var icon: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .screenshots: return "camera.viewfinder"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.fill"
        case .timer: return "timer"
        case .notes: return "note.text"
        case .stats: return "chart.xyaxis.line"
        case .llmUsage: return "chart.bar.doc.horizontal"
        case .terminal: return "apple.terminal"
        }
    }

    /// Whether the feature behind the tab is on; each feature keeps its own switch.
    var isFeatureAvailable: Bool {
        switch self {
        case .nowPlaying:
            return Defaults[.showStandardMediaControls]
                || Defaults[.showCalendar] || Defaults[.showMirror]
        case .screenshots:
            // Merged into the Clipboard tab (step D4).
            return false
        case .clipboard:
            return (Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .notchTab)
                || Defaults[.enableScreenshotShelf]
        case .shelf:
            return Defaults[.dynamicShelf]
        case .timer:
            return Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .tab
        case .notes:
            return Defaults[.enableNotes] || (Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .separateTab)
        case .stats:
            return Defaults[.enableStatsFeature]
        case .llmUsage:
            return Defaults[.enableLLMUsageFeature]
        case .terminal:
            return Defaults[.enableTerminalFeature]
        }
    }

    /// Where to turn the feature on, shown when the tab is unavailable.
    var featureHint: String {
        switch self {
        case .nowPlaying: return String(localized: "Turn on media controls or the calendar in Media settings.")
        case .screenshots: return String(localized: "Turn on “Collect new screenshots” in Screenshots settings.")
        case .clipboard: return String(localized: "Turn on the clipboard and choose the Notch Tab display mode in Clipboard settings.")
        case .shelf: return String(localized: "Turn on the shelf in Shelf settings.")
        case .timer: return String(localized: "Turn on the timer in tab mode in Timer settings.")
        case .notes: return String(localized: "Turn on Notes in Notes settings.")
        case .stats: return String(localized: "Turn on Stats in Stats settings.")
        case .llmUsage: return String(localized: "Turn on the LLM usage monitor in Stats settings.")
        case .terminal: return String(localized: "Turn on the terminal in Terminal settings.")
        }
    }
}

/// Order, visibility and default of the island tabs.
enum NotchTabLayout {
    /// Hidden until turned on in Settings → Island → Layout.
    static let defaultHidden: [NotchTab] = [.timer, .notes, .stats, .llmUsage]

    /// The saved order with duplicates removed and tabs added since appended.
    static func normalizedOrder(_ stored: [NotchTab]) -> [NotchTab] {
        var seen = Set<NotchTab>()
        var result = stored.filter { seen.insert($0).inserted }
        result += NotchTab.defaultOrder.filter { !seen.contains($0) }
        return result
    }

    static func visibleTabs(order: [NotchTab], hidden: [NotchTab], layout: IslandLayout = .standard, isAvailable: (NotchTab) -> Bool) -> [NotchTab] {
        normalizedOrder(order).filter { !hidden.contains($0) && layout.keeps($0) && isAvailable($0) }
    }

    /// Tabs shown in the tab bar, in the user's order.
    static var visibleTabs: [NotchTab] {
        visibleTabs(order: Defaults[.notchTabOrder], hidden: Defaults[.notchHiddenTabs], layout: Defaults[.islandLayout], isAvailable: { $0.isFeatureAvailable })
    }

    static func isVisible(_ tab: NotchTab) -> Bool {
        visibleTabs.contains(tab)
    }

    /// Every view in display order, for the slide direction of tab switches.
    static var directionOrder: [NotchViews] {
        normalizedOrder(Defaults[.notchTabOrder]).map(\.view) + [.extensionExperience]
    }

    /// The tab the island opens on next time, after it closed on `current`.
    /// No default tab means "the last opened one".
    static func viewAfterClose(current: NotchViews, defaultTab: NotchTab?, visible: [NotchTab]) -> NotchViews {
        guard let defaultTab else { return current }
        if visible.contains(defaultTab) { return defaultTab.view }
        return visible.first?.view ?? .home
    }

    /// Moves `tab` to the position of `target` (dropping a row onto another).
    static func move(_ tab: NotchTab, onto target: NotchTab, in order: [NotchTab]) -> [NotchTab] {
        var result = normalizedOrder(order)
        guard tab != target, let from = result.firstIndex(of: tab), let to = result.firstIndex(of: target) else { return result }
        result.remove(at: from)
        result.insert(tab, at: to)
        return result
    }

    /// Whether a file dragged over the island switches it to the shelf. Not
    /// while something is being dragged out of the island itself.
    static func shouldOpenShelfOnFileDrag(enabled: Bool, shelfVisible: Bool, notchClosed: Bool, draggingOutOfIsland: Bool) -> Bool {
        guard shelfVisible, !draggingOutOfIsland else { return false }
        // From a closed island the shelf always opened (upstream behaviour);
        // the setting adds switching while it is already open on another tab.
        return notchClosed || enabled
    }
}
