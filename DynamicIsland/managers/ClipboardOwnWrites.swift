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

/// Clipboard writes made by the app itself, which the clipboard history must
/// not record as new copies.
///
/// Every own write carries the type `io.github.amidamaru940.skerry.own-copy` and its
/// change count is remembered; either is enough to recognise it.
enum ClipboardOwnWrites {
    static let marker = NSPasteboard.PasteboardType("io.github.amidamaru940.skerry.own-copy")

    private static let lock = NSLock()
    private static var ownChangeCounts: [String: Int] = [:]

    /// Clears the pasteboard, lets `write` fill it, and marks the result as ours.
    static func write(to pasteboard: NSPasteboard = .general, _ write: (NSPasteboard) -> Void) {
        pasteboard.clearContents()
        write(pasteboard)
        // Added to the first item, the way nspasteboard.org markers are, so
        // no extra item appears for apps that paste every item.
        pasteboard.addTypes([marker], owner: nil)
        pasteboard.setData(Data(), forType: marker)
        lock.lock()
        ownChangeCounts[pasteboard.name.rawValue] = pasteboard.changeCount
        lock.unlock()
    }

    static func isOwnWrite(_ pasteboard: NSPasteboard) -> Bool {
        if ClipboardCapturePolicy.allTypes(on: pasteboard).contains(marker) { return true }
        lock.lock()
        defer { lock.unlock() }
        return ownChangeCounts[pasteboard.name.rawValue] == pasteboard.changeCount
    }
}
