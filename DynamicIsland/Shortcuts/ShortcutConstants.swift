/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import KeyboardShortcuts
import SwiftUI

// Skerry: no shortcut has a default. Upstream's defaults (⇧⌘V, ⇧⌘P, ⇧⌘A,
// ⇧⌘H, ⇧⌘I, ⇧⌘T, ⇧⌘K, ⌃`, ⌘F1, ⌘F2) took keys from every app, e.g. ⇧⌘T in
// browsers and ⇧⌘A/⇧⌘H/⇧⌘I/⇧⌘K in Finder. The user records the ones they want;
// Settings suggests combinations that are free in macOS and in this app.
extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel")
    static let colorPickerPanel = Self("colorPickerPanel")
    static let screenAssistantPanel = Self("screenAssistantPanel")
    static let decreaseBacklight = Self("decreaseBacklight")
    static let increaseBacklight = Self("increaseBacklight")
    static let toggleSneakPeek = Self("toggleSneakPeek")
    static let toggleNotchOpen = Self("toggleNotchOpen")
    static let toggleTerminalTab = Self("toggleTerminalTab")
    static let startDemoTimer = Self("startDemoTimer")
    static let toggleCaffeinate = Self("toggleCaffeinate")
    /// Suggested: ⌃⌥⌘V.
    static let toggleClipboardPause = Self("toggleClipboardPause")
    /// Opens the island on the Screenshots tab. Suggested: ⌃⌥⌘S.
    static let openScreenshotsTab = Self("openScreenshotsTab")
    /// Play/pause of the current player. Suggested: ⌃⌥⌘P.
    static let playPause = Self("playPause")
}

/// Every global shortcut that can be recorded in Settings, for the duplicate
/// check. (`decreaseBacklight`/`increaseBacklight` have neither a handler nor
/// a recorder upstream.)
enum AppShortcuts {
    struct Entry {
        let name: KeyboardShortcuts.Name
        let title: String
    }

    static var all: [Entry] {
        [
            Entry(name: .toggleNotchOpen, title: String(localized: "Toggle Notch Open")),
            Entry(name: .openScreenshotsTab, title: String(localized: "Open Screenshots")),
            Entry(name: .clipboardHistoryPanel, title: String(localized: "Clipboard History")),
            Entry(name: .toggleClipboardPause, title: String(localized: "Pause Clipboard History")),
            Entry(name: .playPause, title: String(localized: "Play/Pause")),
            Entry(name: .toggleSneakPeek, title: String(localized: "Toggle Sneak Peek")),
            Entry(name: .toggleCaffeinate, title: String(localized: "Toggle Keep Awake")),
            Entry(name: .startDemoTimer, title: String(localized: "Start Demo Timer")),
            Entry(name: .screenAssistantPanel, title: String(localized: "Screen Assistant")),
            Entry(name: .toggleTerminalTab, title: String(localized: "Toggle Terminal Tab")),
            Entry(name: .colorPickerPanel, title: String(localized: "Color Picker Panel")),
        ]
    }

    /// Suggested combinations: free in macOS (checked against the system
    /// shortcuts on macOS 26.6) and used by nothing else in the app.
    static let suggestions: [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut] = [
        .openScreenshotsTab: .init(.s, modifiers: [.control, .option, .command]),
        .clipboardHistoryPanel: .init(.c, modifiers: [.control, .option, .command]),
        .playPause: .init(.p, modifiers: [.control, .option, .command]),
        .toggleClipboardPause: .init(.v, modifiers: [.control, .option, .command]),
    ]
}

enum ShortcutConflicts {
    /// Groups of actions that share one combination (each group in the
    /// order given, groups in the order of their first action). Pressing
    /// such a combination runs all of them.
    static func duplicates(
        in assignments: [(name: KeyboardShortcuts.Name, shortcut: KeyboardShortcuts.Shortcut?)]
    ) -> [[KeyboardShortcuts.Name]] {
        var groups: [KeyboardShortcuts.Shortcut: [KeyboardShortcuts.Name]] = [:]
        var firstSeen: [KeyboardShortcuts.Shortcut] = []
        for (name, shortcut) in assignments {
            guard let shortcut else { continue }
            if groups[shortcut] == nil { firstSeen.append(shortcut) }
            groups[shortcut, default: []].append(name)
        }
        return firstSeen.compactMap { groups[$0]!.count > 1 ? groups[$0] : nil }
    }

    /// The app's shortcuts as recorded now.
    static func current() -> [[KeyboardShortcuts.Name]] {
        duplicates(in: AppShortcuts.all.map { ($0.name, KeyboardShortcuts.getShortcut(for: $0.name)) })
    }
}
