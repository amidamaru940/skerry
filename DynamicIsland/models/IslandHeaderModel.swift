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

import Combine
import Foundation

/// "Something new here" dots on the island tabs, instead of item counts
/// (counts were cut off and almost always on). A tab gets a dot when an
/// item appeared that was not there when the tab was last looked at.
/// Removing items never brings a dot back.
final class TabNewItemsTracker: ObservableObject {
    static let shared = TabNewItemsTracker()

    /// Bumped when a tab is marked seen, so the tab bar redraws.
    @Published private(set) var revision = 0
    private var seen: [NotchTab: Set<String>] = [:]

    /// The first time a tab's items are looked up (the island first shown),
    /// they count as seen.
    func hasNew(_ tab: NotchTab, current: Set<String>) -> Bool {
        if seen[tab] == nil { seen[tab] = current }
        return Self.hasNew(current: current, seen: seen[tab])
    }

    func markSeen(_ tab: NotchTab, current: Set<String>) {
        guard seen[tab] != current else { return }
        seen[tab] = current
        revision += 1
    }

    static func hasNew(current: Set<String>, seen: Set<String>?) -> Bool {
        guard let seen else { return false }
        return !current.isSubset(of: seen)
    }
}

/// The live states shown in the capsule at the right of the island header.
/// Nothing shows when nothing is going on.
enum IslandStatus {
    enum Item: Equatable {
        case recording
        case keepAwake(remaining: TimeInterval?)
        case focus
        case lowBattery(percent: Int)
    }

    static let lowBatteryPercent = 20

    static func items(
        recording: Bool,
        keepAwake: Bool,
        keepAwakeRemaining: TimeInterval?,
        focus: Bool,
        batteryPercent: Float?,
        charging: Bool
    ) -> [Item] {
        var items: [Item] = []
        if recording { items.append(.recording) }
        if keepAwake { items.append(.keepAwake(remaining: keepAwakeRemaining)) }
        if focus { items.append(.focus) }
        if let batteryPercent, !charging, Int(batteryPercent.rounded()) <= lowBatteryPercent {
            items.append(.lowBattery(percent: Int(batteryPercent.rounded())))
        }
        return items
    }
}

/// The "…" button at the right of the island header. It replaces the row
/// of separate header buttons (eyedropper, cup, gear, clipboard, app
/// volume, mirror); each of their panels opens in its place. (The timer
/// lives in its tab only since step D5.)
enum IslandMoreMenu {
    enum Entry: Equatable {
        case keepAwake
        case colorPicker
        case clipboard
        case clipboardPause(paused: Bool)
        case appVolume
        case mirror
        case settings
    }

    /// What the popover shows: the menu, or the panel an entry opened.
    enum Panel: Equatable {
        case menu, keepAwake, colorPicker, clipboard, appVolume
    }

    struct Features: Equatable {
        var keepAwake = true
        var colorPicker = true
        var clipboard = true
        /// The clipboard is not a tab in the bar (panel or popover mode).
        var clipboardOutsideTabs = false
        var clipboardPaused = false
        var appVolume = false
        var mirror = false
    }

    static func entries(for features: Features) -> [Entry] {
        var entries: [Entry] = []
        if features.keepAwake { entries.append(.keepAwake) }
        if features.colorPicker { entries.append(.colorPicker) }
        if features.clipboard && features.clipboardOutsideTabs { entries.append(.clipboard) }
        if features.clipboard { entries.append(.clipboardPause(paused: features.clipboardPaused)) }
        if features.appVolume { entries.append(.appVolume) }
        if features.mirror { entries.append(.mirror) }
        entries.append(.settings)
        return entries
    }

    /// The panel an entry opens inside the popover; nil for entries that act
    /// at once (pause, mirror, settings).
    static func panel(for entry: Entry) -> Panel? {
        switch entry {
        case .keepAwake: return .keepAwake
        case .colorPicker: return .colorPicker
        case .clipboard: return .clipboard
        case .appVolume: return .appVolume
        case .clipboardPause, .mirror, .settings: return nil
        }
    }
}
