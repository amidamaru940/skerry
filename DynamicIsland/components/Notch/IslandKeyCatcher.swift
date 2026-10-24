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
import SwiftUI

/// Keys of one island tab. Takes keyboard focus when empty space in the tab
/// is clicked, and when the island gets the keyboard (a click or a shortcut)
/// while nothing else in it has focus, so the tab's keys work without a
/// further click. It never takes the keyboard from another app: an island
/// opened by hovering is not the key window.
struct IslandKeyCatcher: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool
    /// ⌘-keys that also work while a text field in the same window has the
    /// keyboard: «Буфер»'s search field and its ⌘1…⌘9.
    var onKeyWhileTyping: ((NSEvent) -> Bool)? = nil

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onKey = onKey
        view.onKeyWhileTyping = onKeyWhileTyping
        return view
    }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.onKey = onKey
        view.onKeyWhileTyping = onKeyWhileTyping
    }

    final class KeyCatcherView: NSView {
        var onKey: ((NSEvent) -> Bool)?
        var onKeyWhileTyping: ((NSEvent) -> Bool)?

        override var acceptsFirstResponder: Bool { true }

        /// Keys only, never clicks. It sits behind the screenshot grid in
        /// SwiftUI terms, but AppKit can stack it above the scroll view, and
        /// then it took every click meant for a tile: tiles in the grid could
        /// not be selected. A clicked tile takes the keys itself.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func keyDown(with event: NSEvent) {
            if onKey?(event) != true { super.keyDown(with: event) }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if window?.firstResponder === self, onKey?(event) == true { return true }
            // A field editor has the keyboard: only the keys asked for here.
            if let onKeyWhileTyping, window?.firstResponder is NSText, onKeyWhileTyping(event) { return true }
            return super.performKeyEquivalent(with: event)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Selector observers are dropped automatically when the view goes away.
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification, object: window
            )
            claimFocusIfFree()
            // The previous tab may still be leaving (its transition); try again after it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.claimFocusIfFree() }
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            claimFocusIfFree()
        }

        /// Focus is free when the window itself, or another tab's catcher, has it.
        private func claimFocusIfFree() {
            guard let window, window.isKeyWindow, window.firstResponder !== self else { return }
            if window.firstResponder === window || window.firstResponder is KeyCatcherView {
                window.makeFirstResponder(self)
            }
        }
    }
}
