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
import ApplicationServices

/// Pastes a clipboard entry into the app the user was working in.
///
/// The island is a non-activating panel: after a click in it, key events go
/// to the island while the user's app stays active. So pasting is: put the
/// entry on the clipboard (as the app's own write), close the island, hand
/// activation back to the last app that was in front, then press ⌘V. Pressing
/// keys for another app needs the Accessibility permission; without it the
/// entry is only copied and the user presses ⌘V.
@MainActor
enum ClipboardPaster {
    enum Result: Equatable {
        case pasted
        /// Copied, but ⌘V could not be sent (no Accessibility permission or no target app).
        case copiedOnly
    }

    // Replaced in tests, so nothing is pressed or activated on the machine.
    static var isAccessibilityTrusted: () -> Bool = { AXIsProcessTrusted() }
    static var activateTarget: (NSRunningApplication) -> Void = { $0.activate() }
    static var postPasteKeystroke: () -> Void = { postCommandV() }
    static var pasteDelay: TimeInterval = 0.15

    /// The last app other than Skerry that was in front.
    private(set) static var lastExternalApp: NSRunningApplication?
    private static var activationObserver: NSObjectProtocol?

    /// Starts following which app is in front (called at launch).
    static func trackFrontmostApps() {
        guard activationObserver == nil else { return }
        remember(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { remember(app) }
        }
    }

    static func remember(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastExternalApp = app
        PasteTarget.shared.update(app.localizedName)
    }

    /// Copies `item` (plain text when `plainText` and the entry has text),
    /// closes the island and pastes into the last app in front.
    @discardableResult
    static func paste(
        _ item: ClipboardItem,
        plainText: Bool,
        manager: ClipboardManager = .shared,
        pasteboard: NSPasteboard = .general,
        target: NSRunningApplication? = nil,
        closeIsland: () -> Void
    ) -> Result {
        let hasText = item.stringData != nil || item.type == .file
        return deliver(target: target, closeIsland: closeIsland) {
            manager.copyToClipboard(item, plainText: plainText && hasText, to: pasteboard)
        }
    }

    /// Puts content on the clipboard with `write` (which marks it as the
    /// app's own), then closes the island, hands activation back to the last
    /// app in front and presses ⌘V there. Without Accessibility (or with no
    /// app to paste into) the island stays open, so it can say "press ⌘V".
    @discardableResult
    static func deliver(target: NSRunningApplication? = nil, closeIsland: () -> Void, write: () -> Void) -> Result {
        write()
        guard isAccessibilityTrusted(), let app = target ?? lastExternalApp else { return .copiedOnly }
        closeIsland()
        activateTarget(app)
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            postPasteKeystroke()
        }
        return .pasted
    }

    /// The name of the app a paste goes to, for "Paste into Claude".
    static var targetName: String? {
        lastExternalApp?.localizedName
    }

    /// Presses ⌘V. Key code 9 is the physical V key, so it works in any
    /// keyboard layout (macOS maps ⌘ shortcuts through the Latin layout).
    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
