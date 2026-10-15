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

/// Markup for several screenshots. The system Markup editor takes exactly
/// one image at a time, so they open one after another: the next one when
/// the previous editor is done. Cancelling stops the queue.
@MainActor
final class MarkupQueue: NSObject, NSSharingServiceDelegate {
    static let shared = MarkupQueue()

    /// Opens one file in Markup and returns what has to stay alive while
    /// its editor is open; nil when Markup cannot take the file (a video).
    typealias Opener = (URL, NSSharingServiceDelegate) -> AnyObject?

    private let open: Opener
    private(set) var pending: [URL] = []
    /// The editor open right now.
    private var current: AnyObject?

    init(open: @escaping Opener = MarkupQueue.openInMarkup) {
        self.open = open
    }

    /// Starts over with these files. False when Markup could take none of
    /// them, so the caller can fall back to Preview.
    @discardableResult
    func start(_ urls: [URL]) -> Bool {
        pending = urls
        current = nil
        return openNext()
    }

    /// The editor of the current file closed: saved goes on to the next,
    /// cancelled stops.
    func finished(saved: Bool) {
        current = nil
        if saved {
            openNext()
        } else {
            pending.removeAll()
        }
    }

    @discardableResult
    private func openNext() -> Bool {
        while !pending.isEmpty {
            let url = pending.removeFirst()
            if let editor = open(url, self) {
                current = editor
                return true
            }
        }
        return false
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Task { @MainActor in self.finished(saved: true) }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        Task { @MainActor in self.finished(saved: false) }
    }

    /// The `com.apple.MarkupUI.Markup` extension, the one behind Quick
    /// Look's markup button.
    static func openInMarkup(_ url: URL, delegate: NSSharingServiceDelegate) -> AnyObject? {
        guard let service = NSSharingService(named: NSSharingService.Name("com.apple.MarkupUI.Markup")),
              service.canPerform(withItems: [url]) else { return nil }
        service.delegate = delegate
        service.perform(withItems: [url])
        return service
    }
}
