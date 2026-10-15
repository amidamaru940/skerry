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
import Defaults

/// Lyrics are looked up online, so turning them on (in Settings or with a
/// player button) asks first. Turning them off never asks.
@MainActor
enum LyricsConsent {
    /// Shows the question; replaced in tests.
    static var confirm: () -> Bool = { askWithAlert() }

    static var explanation: String {
        String(localized: "To find lyrics, the title and artist of each track you play are sent to lrclib.net and to NetEase Cloud Music (music.163.com).")
    }

    /// Sets `enableLyrics`, asking before it goes on. Returns the new value.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let value = resolve(requested: enabled, currentlyOn: Defaults[.enableLyrics], confirm: confirm)
        Defaults[.enableLyrics] = value
        return value
    }

    /// The new value: turning on needs a yes; off, or on while on, does not ask.
    static func resolve(requested: Bool, currentlyOn: Bool, confirm: () -> Bool) -> Bool {
        guard requested, !currentlyOn else { return requested }
        return confirm()
    }

    static func toggle() {
        setEnabled(!Defaults[.enableLyrics])
    }

    private static func askWithAlert() -> Bool {
        let wasActive = NSApp.isActive
        // The island is a background panel; bring the question to the front.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Turn on lyrics?")
        alert.informativeText = explanation
        alert.addButton(withTitle: String(localized: "Turn On"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let accepted = alert.runModal() == .alertFirstButtonReturn
        if !wasActive { NSApp.deactivate() }
        return accepted
    }
}
