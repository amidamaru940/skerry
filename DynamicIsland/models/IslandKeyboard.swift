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

/// How the island opens.
enum IslandOpening {
    static let hoverDelayRange: ClosedRange<TimeInterval> = 0...1
    static let hoverDelayStep: TimeInterval = 0.05

    /// Hovering opens the island only with hover opening on. In "Open only
    /// by click" mode nothing opens it on hover, a running timer included
    /// (upstream opened the timer tab on hover even with hover opening off).
    static func opensOnHover(openNotchOnHover: Bool) -> Bool {
        openNotchOnHover
    }

    /// "150 ms" in the user's language.
    static func hoverDelayLabel(seconds: TimeInterval, locale: Locale = .current) -> String {
        let milliseconds = Int((seconds * 1000).rounded())
        return Duration.milliseconds(milliseconds)
            .formatted(.units(allowed: [.milliseconds], width: .abbreviated).locale(locale))
    }
}

/// Keys that work anywhere in the open island while it has keyboard focus
/// (after a click in it or opening it with a shortcut; hovering never takes
/// focus away from the app in front).
enum IslandKeyCommand: Equatable {
    case close
    case nextTab
    case previousTab

    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Arrow keys also carry .function and .numericPad; only these count.
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        switch keyCode {
        case 53 where flags.isEmpty: self = .close           // Esc
        case 124 where flags.isEmpty: self = .nextTab        // →
        case 123 where flags.isEmpty: self = .previousTab    // ←
        case 48 where flags.isEmpty: self = .nextTab         // Tab
        case 48 where flags == .shift: self = .previousTab   // ⇧Tab
        default: return nil
        }
    }
}

/// What a key command does in the island.
enum IslandKeyAction: Equatable {
    case close
    case clearScreenshotSelection
    case show(NotchViews)
}

enum IslandKeyboard {
    /// Esc first clears a screenshot selection, then closes the island.
    /// ←/→ and Tab/⇧Tab go through the visible tabs in the user's order and
    /// wrap around at the ends.
    static func action(
        for command: IslandKeyCommand,
        current: NotchViews,
        visible: [NotchTab],
        hasScreenshotSelection: Bool
    ) -> IslandKeyAction? {
        switch command {
        case .close:
            // Screenshots are chosen in the Clipboard tab now (step D4).
            let showsScreenshots = current == .screenshots || current == .clipboard
            return showsScreenshots && hasScreenshotSelection ? .clearScreenshotSelection : .close
        case .nextTab, .previousTab:
            guard let view = NotchTabLayout.adjacentView(to: current, forward: command == .nextTab, visible: visible),
                  view != current else { return nil }
            return .show(view)
        }
    }
}

extension NotchTabLayout {
    /// The tab after (or before) `current` among `visible`, wrapping around.
    /// From a view that is not a visible tab: the first (or last) tab.
    static func adjacentView(to current: NotchViews, forward: Bool, visible: [NotchTab]) -> NotchViews? {
        guard !visible.isEmpty else { return nil }
        guard let index = visible.firstIndex(where: { $0.view == current }) else {
            return (forward ? visible.first : visible.last)?.view
        }
        let next = (index + (forward ? 1 : -1) + visible.count) % visible.count
        return visible[next].view
    }
}
