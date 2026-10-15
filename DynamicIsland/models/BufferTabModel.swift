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

/// The segments of the Clipboard tab, which now holds the screenshots too
/// (docs/PLAN-DESIGN.md §3.4): everything, the screenshot batches, text,
/// links, files.
enum BufferSegment: String, CaseIterable, Identifiable {
    case all, screenshots, text, links, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .screenshots: return String(localized: "Screenshots")
        case .text: return String(localized: "Text")
        case .links: return String(localized: "Links")
        case .files: return String(localized: "Files")
        }
    }

    /// The clipboard history filter behind the segment; nil for the
    /// screenshot batches.
    var clipboardFilter: ClipboardFilter? {
        switch self {
        case .all: return .all
        case .text: return .text
        case .links: return .links
        case .files: return .files
        case .screenshots: return nil
        }
    }

    /// The segments there is something behind: the history needs the
    /// clipboard shown as a tab, the batches need screenshot collecting.
    static func available(clipboard: Bool, screenshots: Bool) -> [BufferSegment] {
        allCases.filter { segment in
            segment == .screenshots ? screenshots : clipboard
        }
    }

    /// The chosen segment while it is available, otherwise the first one.
    static func resolve(_ chosen: BufferSegment, available: [BufferSegment]) -> BufferSegment? {
        available.contains(chosen) ? chosen : available.first
    }
}

/// Rules of the merged Clipboard tab.
enum BufferLayout {
    /// How long the latest batch stays on top of the history.
    static let stripLifetime: TimeInterval = 24 * 60 * 60

    /// The latest batch sits above the history in "All"; the Screenshots
    /// segment shows every batch instead, and the other segments are about
    /// copies only.
    static func showsBatchStrip(segment: BufferSegment, lastAddedAt: Date?, now: Date) -> Bool {
        guard segment == .all, let lastAddedAt else { return false }
        return now.timeIntervalSince(lastAddedAt) < stripLifetime
    }

    /// "Paste into Claude · 3", or "Copy · 3" when there is no app to paste
    /// into or no permission to press ⌘V.
    static func pasteTitle(count: Int, target: String?, canPaste: Bool) -> String {
        if canPaste, let target, !target.isEmpty {
            return String(format: String(localized: "Paste into %@ · %lld"), target, count)
        }
        return String(format: String(localized: "Copy · %lld"), count)
    }
}

/// The segment the Clipboard tab was left on, kept while the app runs.
@MainActor
final class BufferTabState: ObservableObject {
    static let shared = BufferTabState()
    @Published var segment: BufferSegment = .all
    @Published var query = ""
    /// Pinned entries sit in one folded row on top until opened.
    @Published var showsPinned = false
    /// Feedback after an action that left the island open ("Copied…").
    @Published private(set) var toast: String?
    @Published private(set) var toastIsWarning = true
    private var toastWork: DispatchWorkItem?

    func show(toast text: String, warning: Bool = true, for seconds: TimeInterval = 5) {
        toastWork?.cancel()
        toast = text
        toastIsWarning = warning
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// After ⌘C on screenshots (it gave no sign before).
    static func copiedScreenshots(_ count: Int) -> String {
        String(format: String(localized: "Copied · %lld"), count)
    }

    /// After a paste that could only copy: what to do next.
    static var copiedHint: String {
        String(localized: "Copied. Press ⌘V in your app — allow Accessibility for Skerry to paste in one click.")
    }
}

/// The app a paste goes to, for "Paste into …"; follows `ClipboardPaster`.
@MainActor
final class PasteTarget: ObservableObject {
    static let shared = PasteTarget()
    @Published private(set) var name: String?

    func update(_ name: String?) {
        if self.name != name { self.name = name }
    }
}
