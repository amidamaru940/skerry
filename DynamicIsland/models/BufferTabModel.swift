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
import Defaults
import Foundation
import SwiftUI

/// The segments of the Clipboard tab, which now holds the screenshots too
/// (docs/PLAN-DESIGN.md §3.4): everything, the screenshot batches, text,
/// links, files.
enum BufferSegment: String, CaseIterable, Identifiable {
    case all, screenshots, text, links, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        // «Снимки», the island's word for them (the glossary); Settings
        // keep «Скриншоты».
        case .screenshots: return String(localized: "Shots")
        case .text: return String(localized: "Text")
        case .links: return String(localized: "Links")
        case .files: return String(localized: "Files")
        }
    }

    /// «Все» and «Снимки» show the screenshot batches.
    var showsScreenshots: Bool { self == .all || self == .screenshots }

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

    /// What ⌃⌥⌘S does (Buffer v3): «Буфер» on «Снимки», opening the island
    /// when it is closed or on another tab; pressed again on «Снимки», the
    /// island closes; on another filter it only moves to «Снимки».
    struct ShotsShortcut: Equatable {
        /// The filter moves to «Снимки» (the person asked for them).
        var showsShots: Bool
        /// The island's «Буфер» tab is toggled: opened, or closed.
        var togglesTab: Bool
    }

    static func shotsShortcut(islandOpen: Bool, onBuffer: Bool, segment: BufferSegment) -> ShotsShortcut {
        let onShots = islandOpen && onBuffer && segment == .screenshots
        return ShotsShortcut(showsShots: !onShots, togglesTab: onShots || !islandOpen || !onBuffer)
    }

    /// A new screenshot opens «Буфер» on «Все», where the new batch's film and
    /// its key are, unless «Снимки» already shows it.
    static func segmentAfterCapture(_ segment: BufferSegment) -> BufferSegment {
        segment == .screenshots ? .screenshots : .all
    }

    /// «Очистить» in the island's «…» and the trash: on every filter (on
    /// «Снимки» its «Отменить» rides a capsule), never while the screen is
    /// shared (the content is hidden then, and a clear would go unseen).
    static func offersClearHistory(segment: BufferSegment?, hidingContent: Bool) -> Bool {
        !hidingContent && segment != nil
    }

    /// The history's «Отменить» line lives in the history; anywhere else on
    /// the tab (moved to «Снимки» during the offer) a capsule carries it.
    static func clearedUndoNeedsCapsule(segment: BufferSegment?, undo: BufferUndo.Kind?) -> Bool {
        undo == .history && segment?.clipboardFilter == nil
    }
}

/// How tall the open island is on the Clipboard tab: as tall as what it
/// shows. It always opened at the full grid height, so an empty clipboard was
/// a large black square around one line. Between the compact Now height and
/// the full grid height; past that the grid scrolls.
enum BufferFit {
    static let minimum: CGFloat = compactHomeOpenHeight
    /// The film, its action row and three rows of copies (Buffer v3: 354).
    static let maximum: CGFloat = 354
    /// Reported by content that wants all the room there is (the screenshot
    /// grid).
    static let wantsAllRoom: CGFloat = -10_000

    /// The height that leaves no empty space under the content. `slack` is
    /// the room left over below it at the `current` height, negative when the
    /// content scrolls; nil when nothing was measured.
    static func height(current: CGFloat, slack: CGFloat?) -> CGFloat {
        guard let slack else { return maximum }
        return min(max((current - slack).rounded(), minimum), maximum)
    }

    /// Small differences are measuring noise, not a reason to move the island.
    static func isWorthChanging(from old: CGFloat, to new: CGFloat) -> Bool {
        abs(new - old) >= 2
    }
}

/// The room left over under the Clipboard tab's content (see `BufferFit`).
struct BufferSlackKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}

/// Fills the space under content that does not scroll, and reports it: the
/// room from its top to the bottom of the tab (`BufferTabFrame`), negative
/// when the content above runs past the island. Its own height cannot say
/// that: an overflowing stack lays it out at 0, so an island fitted to «No
/// copies yet» never grew back for the film and its paste key (23.10).
/// It must be the last view down to the tab's bottom edge: anything below
/// it would count as room and be cut off. Outside a `BufferTabFrame` it
/// reports its own height.
struct BufferSlackFiller: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: BufferSlackKey.self, value: BufferTabFrame.room(below: geo) ?? geo.size.height)
        }
    }
}

/// The Clipboard tab's frame: exactly the room the island gives it, never
/// the content's height (`minHeight: 0`), so `BufferSlackFiller` sees the
/// content run past it.
struct BufferTabFrame: ViewModifier {
    static let space = "bufferTab"

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(.named(Self.space))
    }

    /// The room from the top of `geo` to the bottom of the tab, negative when
    /// the content above runs past it; nil outside a `BufferTabFrame`.
    static func room(below geo: GeometryProxy) -> CGFloat? {
        let top = geo.frame(in: .named(space)).minY
        return geo.bounds(of: .named(space)).map { $0.height - top }
    }
}

/// Reports the slack under a scrolling list on the Clipboard tab: the room
/// from its top to the bottom of the tab, minus `contentHeight`. Its own
/// height, squeezed to 0 under a film that ran past the island, reported
/// only the rows: the fit fell short and the island stayed cut until it was
/// reopened (23.10). Never more than its own height, so space below it does
/// not count as room.
struct BufferScrollSlack: ViewModifier {
    let contentHeight: CGFloat
    @State private var visible: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { geo in
                min(BufferTabFrame.room(below: geo) ?? geo.size.height, geo.size.height)
            } action: { visible = $0 }
            .preference(key: BufferSlackKey.self, value: visible - contentHeight)
    }
}

/// The segment the Clipboard tab was left on, kept while the app runs.
@MainActor
final class BufferTabState: ObservableObject {
    static let shared = BufferTabState()
    /// The open island's height on this tab (see `BufferFit`).
    @Published private(set) var openHeight: CGFloat = BufferFit.maximum
    private var fitWork: DispatchWorkItem?

    /// Takes the room left under the content and resizes the island to fit,
    /// once the layout has settled: the island's own resize re-measures it.
    func fit(slack: CGFloat?) {
        fitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let fitted = BufferFit.height(current: self.openHeight, slack: slack)
            if BufferFit.isWorthChanging(from: self.openHeight, to: fitted) {
                self.openHeight = fitted
            }
        }
        fitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
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

    // MARK: «Отменить» (Q26)

    /// Removed entries, put back by «Отменить» for `undoLifetime`.
    @Published private(set) var undo: BufferUndo?
    private var undoWork: DispatchWorkItem?
    static let undoLifetime: TimeInterval = 5

    /// × on a row: the row says «Запись удалена — Отменить» where it was.
    /// `index` is its place in its section on screen.
    func delete(_ item: ClipboardItem, shownAt index: Int, pinned: Bool, manager: ClipboardManager = .shared) {
        let removal = manager.remove(item)
        guard !removal.isEmpty else { return }
        offer(BufferUndo(kind: .row(itemID: item.id, index: index, pinned: pinned), removal: removal), manager: manager)
    }

    /// The trash in the header, and «Очистить» in the island's «…»:
    /// everything `segment` shows goes — its copies (pinned ones stay) and,
    /// on «Все» and «Снимки», the screenshots — with no question, one line
    /// with «Отменить» instead. «Очистить историю» took the copies alone, so
    /// with only screenshots in «Буфер» it seemed to do nothing (23.10).
    func clear(_ segment: BufferSegment, manager: ClipboardManager = .shared, shots: ScreenshotShelfManager = .shared) {
        let removal = segment.clipboardFilter.map { manager.removeHistory(matching: $0) } ?? ClipboardManager.Removal()
        let taken = segment.showsScreenshots && Defaults[.enableScreenshotShelf] ? shots.takeOutShown() : ScreenshotBatchStore.Removal()
        guard !removal.isEmpty || !taken.isEmpty else { return }
        offer(BufferUndo(kind: .history, removal: removal, screenshots: taken), manager: manager, shots: shots)
    }

    /// How many entries a clear of `segment` would take.
    static func clearableCount(
        _ segment: BufferSegment?,
        history: [ClipboardItem],
        shownShots: Int
    ) -> Int {
        guard let segment else { return 0 }
        let copies = segment.clipboardFilter.map { filter in history.filter { filter.matches($0.type) }.count } ?? 0
        return copies + (segment.showsScreenshots ? shownShots : 0)
    }

    /// Puts the removed entries back.
    func undoRemoval(manager: ClipboardManager = .shared, shots: ScreenshotShelfManager = .shared) {
        guard let undo else { return }
        undoWork?.cancel()
        undoWork = nil
        self.undo = nil
        manager.restore(undo.removal)
        if !undo.screenshots.isEmpty { shots.restore(undo.screenshots) }
    }

    /// The offer is over: the removed entries' files go.
    func finishUndo(manager: ClipboardManager = .shared, shots: ScreenshotShelfManager = .shared) {
        guard let undo else { return }
        undoWork?.cancel()
        undoWork = nil
        self.undo = nil
        manager.finishRemoval(undo.removal)
        if !undo.screenshots.isEmpty { shots.finishTakeOut(undo.screenshots) }
    }

    private func offer(_ next: BufferUndo, manager: ClipboardManager, shots: ScreenshotShelfManager = .shared) {
        // One offer at a time: a second removal ends the first.
        finishUndo(manager: manager, shots: shots)
        undo = next
        // One timer per removal, not a tick: nothing runs while idle.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.finishUndo(manager: manager, shots: shots) }
        }
        undoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoLifetime, execute: work)
    }

    // MARK: Search

    /// The field is open in place of the filter words. Kept here with the
    /// query, not in the view: the view is made anew each time the island
    /// opens, and a query left behind filtered the list invisibly.
    @Published var searching = false

    func openSearch() {
        searching = true
    }

    /// × on an empty query, Esc, «Снимки»: the field closes and the query goes.
    func closeSearch() {
        searching = false
        if !query.isEmpty { query = "" }
    }

    /// The tab left the screen (the island closed, after ↩ pasted the first
    /// find too, or another tab): no search waits for the next opening.
    func tabDisappeared() {
        closeSearch()
    }

    /// Return in the search field: the history pastes its first find.
    @Published private(set) var searchSubmits = 0
    var searchSubmitShift = false

    func submitSearch(plainText: Bool = false) {
        searchSubmitShift = plainText
        searchSubmits &+= 1
    }

    /// After ⌘C on screenshots (it gave no sign before).
    static func copiedScreenshots(_ count: Int) -> String {
        String(format: String(localized: "Copied · %lld"), count)
    }

    /// «Скопировано · N» once `copy` has written the clipboard, with the
    /// number that really went; nothing when none did or it was stopped.
    static func showCopied(after copy: Task<Int, Never>) {
        Task { @MainActor in
            let count = await copy.value
            guard count > 0 else { return }
            shared.show(toast: copiedScreenshots(count), warning: false, for: 2)
        }
    }

    /// After a paste that could only copy: what to do next.
    static var copiedHint: String {
        String(localized: "Copied. Press ⌘V in your app — allow Accessibility for Skerry to paste in one click.")
    }

    /// After a one-by-one paste stopped mid-way (another app came forward,
    /// the island opened): the rest are copied together.
    static var pasteStoppedHint: String {
        String(localized: "Paste stopped. The rest are copied: press ⌘V in your app.")
    }
}

/// Removed history, with «Отменить» (Buffer v3, Q26).
struct BufferUndo: Identifiable {
    enum Kind: Equatable {
        /// One row; `index` is its place in its section, `pinned` the section.
        case row(itemID: UUID, index: Int, pinned: Bool)
        /// The trash, «Очистить»: what the filter showed.
        case history
    }

    let id = UUID()
    let kind: Kind
    let removal: ClipboardManager.Removal
    var screenshots = ScreenshotBatchStore.Removal()

    /// Copies and screenshots taken together.
    var count: Int { removal.count + screenshots.count }

    /// «Очищено · 14».
    static func clearedMessage(_ count: Int) -> String {
        String(format: String(localized: "Cleared · %lld"), count)
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
