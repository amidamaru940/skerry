/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 * Modified for Skerry (personal fork) in 2026.
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

import SwiftUI
import AppKit
import Defaults
import ImageIO

/// The Clipboard tab: filters and search, pinned items on top, then recent
/// copies. Click copies an item back, double-click or Return pastes it into
/// the app in front (Shift: as plain text), ⌘1…⌘9 paste the numbered items,
/// entries drag out to other apps. In the merged «Буфер» tab (`embedded`)
/// the entries are Buffer v3 rows: two columns of 22 pt rows, the number
/// first, the time last, pin and × under the pointer, «Отменить» after a
/// removal. Also used, with two fixed columns of cards, as the clipboard
/// half of the Notes tab in "separate tab" mode.
struct NotchClipboardView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.clipboardHistoryPaused) private var paused
    @ObservedObject private var presentation = ScreenPresentation.shared
    /// Holds the island open while a card is dragged out of it.
    @State private var dragToken = UUID()
    /// What the grid's cards need, for the island to fit them
    /// (`BufferScrollSlack`, `BufferFit`).
    @State private var scrollContentHeight: CGFloat = 0
    @State private var filter: ClipboardFilter = .all
    @State private var query = ""
    @State private var hoveredItemId: UUID?
    @State private var justCopiedId: UUID?
    @State private var selectedId: UUID?
    @State private var showClearHistoryAlert = false
    @State private var pasteHint = false
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false
    @State private var autoCloseToken = UUID()
    /// ⌘ is down: the row numbers read ⌘1…⌘9.
    @State private var commandHeld = false
    @State private var flagsMonitor: Any?

    /// Inside the merged Clipboard tab (`BufferTabView`), which owns the
    /// filters, search, pause and the pinned toggle; this view shows only
    /// the history.
    var embedded = false
    /// Keys the merged tab adds when this view has the keyboard (the latest
    /// batch's space, ⌘A, ⌘C, Delete).
    var onOtherKey: ((NSEvent) -> Bool)? = nil
    @ObservedObject private var bufferState = BufferTabState.shared

    /// Minimum card width; drives how many columns the adaptive grid shows.
    var minCardWidth: CGFloat = 200
    /// Force an exact column count (the narrow `.separateTab` panel). nil = adaptive by width.
    var fixedColumns: Int? = nil

    private var columns: [GridItem] {
        if let n = fixedColumns {
            return Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, n))
        }
        return [GridItem(.adaptive(minimum: minCardWidth, maximum: .infinity), spacing: 8)]
    }

    private var activeFilter: ClipboardFilter {
        embedded ? (bufferState.segment.clipboardFilter ?? .all) : filter
    }

    private var activeQuery: String { embedded ? bufferState.query : query }

    private var pinned: [ClipboardItem] {
        ClipboardFiltering.apply(clipboardManager.pinnedItems, filter: activeFilter, query: activeQuery)
    }

    private var recent: [ClipboardItem] {
        ClipboardFiltering.apply(clipboardManager.clipboardHistory, filter: activeFilter, query: activeQuery)
    }

    /// Pinned entries are folded in the merged tab until the pin in the
    /// filter row opens them; always open while searching, and when there
    /// is nothing recent to show instead.
    private var showsPinnedCards: Bool {
        !embedded || bufferState.showsPinned || !activeQuery.isEmpty || recentRows.isEmpty
    }

    /// The pinned and recent rows, with «Запись удалена — Отменить» where a
    /// removed one was.
    private var pinnedRows: [ClipboardRowEntry] { ClipboardRowEntry.rows(pinned, undo: bufferState.undo?.kind, pinnedSection: true) }
    private var recentRows: [ClipboardRowEntry] {
        embedded ? ClipboardRowEntry.rows(recent, undo: bufferState.undo?.kind, pinnedSection: false) : recent.map { .item($0) }
    }

    /// Order of the ⌘1…⌘9 numbers: the pinned on screen first, then recent.
    /// A removed row keeps its number until «Отменить» is over.
    private var numbered: [ClipboardItem?] {
        guard embedded else { return (showsPinnedCards ? pinned : []) + recent }
        return ((showsPinnedCards ? pinnedRows : []) + recentRows).map(\.item)
    }

    /// Something to list: entries, or the row of one just removed.
    private var hasEntries: Bool {
        !clipboardManager.clipboardHistory.isEmpty || !clipboardManager.pinnedItems.isEmpty
            || (embedded && { if case .row = bufferState.undo?.kind { return true } else { return false } }())
    }

    var body: some View {
        if presentation.isHidingContent {
            PresentingPlaceholder(title: NotchTab.clipboard.title, icon: NotchTab.clipboard.icon)
        } else {
            clipboardContent
        }
    }

    private var clipboardContent: some View {
        VStack(spacing: 0) {
            if !embedded {
                header
            }
            if pasteHint {
                Text("Copied. Press ⌘V to paste — allow Accessibility for Skerry to paste automatically.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }
            if paused {
                pausedBanner
            }
            if embedded, bufferState.undo?.kind == .history, let undo = bufferState.undo {
                clearedRow(undo)
            }
            if !hasEntries {
                if !paused && !(embedded && bufferState.undo?.kind == .history) { emptyState }
                BufferSlackFiller()
            } else {
                ScrollView {
                    Group {
                        if embedded {
                            rowsContent
                        } else {
                            cardsContent
                        }
                    }
                    .padding(.horizontal, embedded ? 0 : 20)
                    .padding(.bottom, embedded ? 8 : 16)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollContentHeight = $0 }
                }
                .scrollIndicators(embedded ? .never : .automatic)
                // The island shrinks to the rows when they leave room below,
                // and grows past a film that ran over it.
                .modifier(BufferScrollSlack(contentHeight: scrollContentHeight))
            }
        }
        // Embedded, from the top: centred, an overflow moved the rows up by
        // half a notice and the fit took two steps.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: embedded ? .top : .center)
        .animation(.easeOut(duration: 0.2), value: bufferState.undo?.id)
        // Return / ⌘1…⌘9 also work after a click on empty space in the tab,
        // and right away when the island was opened with a shortcut.
        .background(IslandKeyCatcher(onKey: handleKey, onKeyWhileTyping: embedded ? handleSearchKey : nil))
        .onHover { updateSuppression(for: $0) }
        .onDisappear {
            stopWatchingCommand()
            updateSuppression(for: false)
            vm.setAutoCloseSuppression(false, token: autoCloseToken)
            vm.setAutoCloseSuppression(false, token: dragToken)
        }
        .alert("Clear Clipboard History?", isPresented: $showClearHistoryAlert) {
            Button("Clear History", role: .destructive) { clipboardManager.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every recent clipboard item. Pinned items stay.")
        }
        .onChange(of: showClearHistoryAlert) { _, isShowing in
            vm.setAutoCloseSuppression(isShowing, token: autoCloseToken)
        }
        // Return in the search field pastes the first find.
        .onChange(of: bufferState.searchSubmits) {
            guard embedded, let first = numbered.compactMap({ $0 }).first else { return }
            paste(first, plainText: bufferState.searchSubmitShift)
        }
        .onAppear {
            if Defaults[.enableClipboardManager], !clipboardManager.isMonitoring {
                clipboardManager.startMonitoring()
            }
            if embedded { startWatchingCommand() }
        }
    }

    /// The Notes tab's cards (as before Buffer v3).
    private var cardsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !pinned.isEmpty {
                sectionTitle("Pinned", systemImage: "pin.fill")
                grid(pinned, numberOffset: 0)
            }
            if !recent.isEmpty {
                if !pinned.isEmpty { sectionTitle("Recent", systemImage: "clock") }
                grid(recent, numberOffset: pinned.count)
            }
            if pinned.isEmpty && recent.isEmpty {
                nothingMatches
            }
        }
    }

    /// Buffer v3: «ЗАКРЕПЛЁННЫЕ · N» when open, «НЕДАВНЕЕ», each a section
    /// head over two columns of rows.
    private var rowsContent: some View {
        let pinnedRows = showsPinnedCards ? self.pinnedRows : []
        let recentRows = self.recentRows
        let searching = !activeQuery.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            if !pinnedRows.isEmpty {
                SectionHeader("\(String(localized: "Pinned")) · \(pinned.count)")
                rowColumns(pinnedRows, numberOffset: 0, pinnedSection: true)
                    .padding(.bottom, 12)
            }
            if !recentRows.isEmpty {
                SectionHeader(searching
                    ? "\(String(localized: "Recent items")) · \(recent.count)"
                    : String(localized: "Recent items"))
                rowColumns(recentRows, numberOffset: pinnedRows.count, pinnedSection: false)
            }
            if pinnedRows.isEmpty && recentRows.isEmpty {
                nothingMatches
            }
        }
    }

    private var nothingMatches: some View {
        Text("Nothing matches")
            .font(embedded ? DSE.Typeface.caption : .caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, embedded ? 12 : 20)
    }

    /// ⌘ shows the numbers as ⌘1…⌘9. Only modifier changes reach it, only
    /// while the tab is on screen: nothing runs while idle.
    private func startWatchingCommand() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            MainActor.assumeIsolated {
                if held != commandHeld { commandHeld = held }
            }
            return event
        }
    }

    private func stopWatchingCommand() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        commandHeld = false
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Clipboard")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                searchField
                Button {
                    paused.toggle()
                } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(paused ? .orange : .white.opacity(0.8))
                        .frame(width: 24, height: 22)
                        .background(Color.white.opacity(paused ? 0.15 : 0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(paused ? "Resume clipboard history" : "Pause clipboard history")
                .accessibilityLabel(Text(paused ? "Resume clipboard history" : "Pause clipboard history"))
                Button(action: { showClearHistoryAlert = true }) {
                    Label("Clear all", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(clipboardManager.clipboardHistory.isEmpty)
                .help("Clear all recent clipboard items")
            }
            HStack(spacing: 4) {
                ForEach(ClipboardFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: filter == option ? .semibold : .regular))
                            .foregroundStyle(filter == option ? .black : .white.opacity(0.75))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(filter == option ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
                Spacer(minLength: 0)
                if paused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 150)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.top, 2)
    }

    @ViewBuilder
    private var emptyState: some View {
        if embedded {
            // One centred line, no plate (Buffer v3, state 10).
            NoticeRow(
                symbol: "doc.on.clipboard",
                title: String(localized: "No copies yet"),
                message: String(localized: "Copy something to see it here"),
                centered: true
            )
            .padding(.top, 8)
        } else {
            DSEmptyState(
                symbol: "doc.on.clipboard",
                title: String(localized: "No copies yet"),
                message: String(localized: "Copy something to see it here"),
                inline: true
            )
        }
    }

    /// One calm line instead of an empty screen that said "paused" and
    /// "copy something" at once. Buffer v3: a 32 pt notice row on a
    /// hairline, the «Возобновить» key, no plate.
    @ViewBuilder
    private var pausedBanner: some View {
        if embedded {
            VStack(spacing: 0) {
                NoticeRow(
                    symbol: "pause.circle",
                    tint: DS.Palette.paused,
                    title: String(localized: "Clipboard history is paused"),
                    message: String(localized: "new copies and shots are not saved"),
                    actionTitle: String(localized: "Resume"),
                    action: { paused = false }
                )
                Hairline()
            }
            .padding(.bottom, 12)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(DS.Palette.paused)
                Text("Clipboard history is paused")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.text)
                Spacer(minLength: 8)
                Button(String(localized: "Resume")) { paused = false }
                    .buttonStyle(DSButtonStyle(kind: .secondary, height: 24))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Palette.card))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    /// «История очищена · 14 записей — Отменить», where the history was.
    private func clearedRow(_ undo: BufferUndo) -> some View {
        VStack(spacing: 0) {
            NoticeRow(
                symbol: "trash",
                title: BufferUndo.clearedMessage(undo.count),
                actionTitle: String(localized: "Undo"),
                action: { bufferState.undoRemoval() }
            )
            Hairline()
        }
        .padding(.bottom, 12)
        .transition(.opacity)
    }

    // MARK: Rows (the merged tab)

    /// Two columns of 22 pt rows, newest first down the left column and on
    /// down the right; a hairline in the 24 pt gutter.
    private func rowColumns(_ entries: [ClipboardRowEntry], numberOffset: Int, pinnedSection: Bool) -> some View {
        let split = ClipboardRowText.leftColumnCount(entries.count)
        return HStack(alignment: .top, spacing: ClipboardRowText.gutter) {
            rowColumn(Array(entries.prefix(split)), firstIndex: 0, numberOffset: numberOffset, pinnedSection: pinnedSection)
            rowColumn(Array(entries.dropFirst(split)), firstIndex: split, numberOffset: numberOffset, pinnedSection: pinnedSection)
        }
        .background { Hairline(axis: .vertical) }
    }

    private func rowColumn(_ entries: [ClipboardRowEntry], firstIndex: Int, numberOffset: Int, pinnedSection: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                let index = firstIndex + offset
                switch entry {
                case .item(let item):
                    // A picture's preview opens past the column's outer
                    // edge, beside the island, never over the list.
                    row(item, number: numberOffset + index + 1, index: index, pinnedSection: pinnedSection,
                        previewEdge: firstIndex == 0 ? .leading : .trailing)
                case .removed:
                    RemovedClipboardRow { bufferState.undoRemoval() }
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ item: ClipboardItem, number: Int, index: Int, pinnedSection: Bool, previewEdge: Edge) -> some View {
        let isPinned = clipboardManager.pinnedItems.contains { $0.id == item.id }
        let isHovered = hoveredItemId == item.id
        let justCopied = justCopiedId == item.id
        return ClipboardRow(
            item: item,
            number: number <= 9 ? number : nil,
            commandHeld: commandHeld,
            isPinned: isPinned,
            showsTools: isHovered,
            isSelected: selectedId == item.id,
            justCopied: justCopied,
            previewEdge: previewEdge
        )
        // A picture says the same in its preview: no tooltip on top of it.
        .overlay(interaction(for: item, tooltip: item.type == .image ? nil : ClipboardRowText.tooltip(for: item)))
        .overlay(alignment: .trailing) {
            if isHovered {
                HStack(spacing: ClipboardRow.toolGap) {
                    GlyphButton(symbol: isPinned ? "pin.slash" : "pin",
                                label: isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                                font: ClipboardRow.toolFont, box: ClipboardRow.toolBox) {
                        clipboardManager.togglePin(for: item)
                    }
                    GlyphButton(symbol: "xmark", label: String(localized: "Delete this item"),
                                font: ClipboardRow.toolFont, box: ClipboardRow.toolBox) {
                        bufferState.delete(item, shownAt: index, pinned: pinnedSection)
                    }
                }
            } else if isPinned && !justCopied {
                // The pin a pinned row wears: a click unpins it.
                GlyphButton(symbol: "pin.fill", label: String(localized: "Unpin"),
                            font: ClipboardRow.toolFont, box: ClipboardRow.toolBox, tint: DSE.Palette.text) {
                    clipboardManager.togglePin(for: item)
                }
            }
        }
        .onHover { hovering in
            if hovering { hoveredItemId = item.id } else if hoveredItemId == item.id { hoveredItemId = nil }
        }
        .accessibilityElement(children: .combine)
        // A picture row labels itself once its thumbnail tells the size.
        .modifier(ClipboardRowLabel(text: item.type == .image ? nil : ClipboardRowText.accessibilityLabel(for: item)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { copy(item) }
        .accessibilityAction(named: Text("Paste")) { paste(item, plainText: false) }
        .accessibilityAction(named: Text(isPinned ? "Unpin" : "Pin")) { clipboardManager.togglePin(for: item) }
        .accessibilityAction(named: Text("Delete")) { bufferState.delete(item, shownAt: index, pinned: pinnedSection) }
    }

    /// Click copies, double-click pastes, drag carries the entry out.
    private func interaction(for item: ClipboardItem, tooltip: String? = nil) -> ClipboardCardInteraction {
        ClipboardCardInteraction(
            writers: { ClipboardDragWriters.writers(for: item) },
            dragImage: { item.type == .image ? item.getImageData().flatMap(NSImage.init(data:)) : nil },
            tooltip: tooltip,
            onClick: { copy(item) },
            onDoubleClick: { shift in paste(item, plainText: shift) },
            onDragChanged: { dragging in
                if dragging { clipboardManager.dragBegan() } else { clipboardManager.dragEnded() }
                vm.setAutoCloseSuppression(dragging, token: dragToken)
                // Dropped outside: close if the pointer is no longer over the island.
                if !dragging { vm.shouldRecheckHover.toggle() }
            },
            onKey: handleKey
        )
    }

    // MARK: Grid

    private func grid(_ items: [ClipboardItem], numberOffset: Int) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                let number = numberOffset + offset + 1
                ClipboardCard(
                    item: item,
                    number: number <= 9 ? number : nil,
                    isHovered: hoveredItemId == item.id,
                    isSelected: selectedId == item.id,
                    justCopied: justCopiedId == item.id
                )
                .overlay(interaction(for: item))
                .overlay(alignment: .topTrailing) { cardButtons(item) }
                .onHover { hovering in
                    if hovering { hoveredItemId = item.id } else if hoveredItemId == item.id { hoveredItemId = nil }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.type.displayName): \(item.preview)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { copy(item) }
                .accessibilityAction(named: Text("Paste")) { paste(item, plainText: false) }
                .accessibilityAction(named: Text("Delete")) { delete(item) }
            }
        }
    }

    @ViewBuilder
    private func cardButtons(_ item: ClipboardItem) -> some View {
        if hoveredItemId == item.id {
            let isPinned = clipboardManager.pinnedItems.contains { $0.id == item.id }
            HStack(spacing: 2) {
                Button { clipboardManager.togglePin(for: item) } label: {
                    Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin" : "Pin")
                Button { delete(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Delete this item")
            }
            .padding(4)
            .transition(.opacity)
        }
    }

    // MARK: Actions

    private func copy(_ item: ClipboardItem) {
        selectedId = item.id
        clipboardManager.copyToClipboard(item)
        withAnimation { justCopiedId = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if justCopiedId == item.id { withAnimation { justCopiedId = nil } }
        }
    }

    private func paste(_ item: ClipboardItem, plainText: Bool) {
        selectedId = item.id
        let result = ClipboardPaster.paste(item, plainText: plainText, closeIsland: { vm.close() })
        if result == .copiedOnly {
            // The island stays open, so the hint can be read.
            if embedded {
                bufferState.show(toast: BufferTabState.copiedHint)
            } else {
                pasteHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { pasteHint = false }
            }
        }
    }

    private func delete(_ item: ClipboardItem) {
        if clipboardManager.pinnedItems.contains(where: { $0.id == item.id }) {
            clipboardManager.unpinItem(item)
        }
        clipboardManager.deleteItem(item)
    }

    /// Return / Enter pastes the selected item, ⌘1…⌘9 the numbered ones;
    /// Shift pastes as plain text.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let action = ClipboardKeyAction(event: event) else { return onOtherKey?(event) ?? false }
        let items = numbered
        switch action {
        case .pasteSelected(let plain):
            let present = items.compactMap { $0 }
            guard let item = present.first(where: { $0.id == selectedId }) ?? present.first else { return false }
            paste(item, plainText: plain)
        case .pasteNumber(let index, let plain):
            guard items.indices.contains(index), let item = items[index] else { return false }
            paste(item, plainText: plain)
        }
        return true
    }

    /// ⌘1…⌘9 from the search field paste the numbered finds (the board,
    /// row 12); every other key stays the field's.
    private func handleSearchKey(_ event: NSEvent) -> Bool {
        guard bufferState.searching, case .pasteNumber(let index, let plain)? = ClipboardKeyAction(event: event) else { return false }
        let items = numbered
        guard items.indices.contains(index), let item = items[index] else { return false }
        paste(item, plainText: plain)
        return true
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}

/// Keys of the Clipboard tab.
enum ClipboardKeyAction: Equatable {
    case pasteSelected(plainText: Bool)
    /// Zero-based index into the numbered items (⌘1 is 0).
    case pasteNumber(Int, plainText: Bool)

    init?(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let plain = flags.contains(.shift)
        if keyCode == 36 || keyCode == 76, flags.subtracting(.shift).isEmpty {     // Return, Enter
            self = .pasteSelected(plainText: plain)
            return
        }
        // Digits by key code, so ⌘1…⌘9 work in any keyboard layout.
        let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        if flags.subtracting(.shift) == .command, let digit = digitKeys[keyCode] {
            self = .pasteNumber(digit - 1, plainText: plain)
            return
        }
        return nil
    }

    init?(event: NSEvent) {
        self.init(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
    }
}

/// One clipboard entry: source app and time, then the content.
struct ClipboardCard: View {
    let item: ClipboardItem
    let number: Int?
    let isHovered: Bool
    let isSelected: Bool
    let justCopied: Bool

    @State private var cachedImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                SourceAppIcon(bundleID: item.sourceBundleID)
                Text(DayTimeLabel.make(for: item.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                // No pin mark here: pinned cards only appear under "Pinned",
                // and the hover button pins and unpins.
                Spacer(minLength: 0)
                if justCopied {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green)
                } else if let number, !isHovered {
                    Text("⌘\(number)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            content
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(isHovered ? DS.Palette.raised : DS.Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(isSelected ? DS.Palette.accent : DS.Palette.separator, lineWidth: isSelected ? 1.5 : 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .task(id: item.id) {
            cachedImage = item.type == .image ? item.getImageData().flatMap(NSImage.init(data:)) : nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            // The picture itself, large, instead of "Image (5.3 MB)".
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(DS.Palette.raised)
                if let cachedImage {
                    Image(nsImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .accessibilityLabel(Text("Picture"))
        case .file:
            let names = (item.fileURLs ?? []).compactMap { URL(string: $0)?.lastPathComponent }
            VStack(alignment: .leading, spacing: 2) {
                Label(ClipboardCardText.fileTitle(names: names), systemImage: names.count > 1 ? "doc.on.doc" : "doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                if names.count > 1 {
                    Text(names.joined(separator: ", "))
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(2)
                }
            }
        case .url:
            let link = ClipboardCardText.link(item.stringData ?? item.preview)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.host)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                if !link.rest.isEmpty {
                    Text(link.rest)
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(2)
                }
            }
        case .text, .rtf, .unknown:
            Text(item.stringData ?? item.preview)
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.text)
                .lineLimit(3)
        }
    }
}

/// One row of the merged tab's list: an entry, or the place of one just
/// removed while «Отменить» is offered.
enum ClipboardRowEntry: Identifiable, Equatable {
    case item(ClipboardItem)
    case removed(UUID)

    var id: UUID {
        switch self {
        case .item(let item): return item.id
        case .removed(let id): return id
        }
    }

    var item: ClipboardItem? {
        if case .item(let item) = self { return item }
        return nil
    }

    static func == (lhs: ClipboardRowEntry, rhs: ClipboardRowEntry) -> Bool {
        switch (lhs, rhs) {
        case (.item(let a), .item(let b)): return a.id == b.id
        case (.removed(let a), .removed(let b)): return a == b
        default: return false
        }
    }

    /// The section's rows, with the removed one back at its place.
    static func rows(_ items: [ClipboardItem], undo: BufferUndo.Kind?, pinnedSection: Bool) -> [ClipboardRowEntry] {
        var rows = items.map { ClipboardRowEntry.item($0) }
        if case .row(let id, let index, let pinned)? = undo, pinned == pinnedSection, !items.contains(where: { $0.id == id }) {
            rows.insert(.removed(id), at: min(max(index, 0), rows.count))
        }
        return rows
    }
}

/// One clipboard entry as a 22 pt row (Buffer v3): its number (⌘N while ⌘
/// is held), the icon of the app it came from, a colour as a swatch, the
/// text on one line, the time. Under the pointer the list's pin and × take
/// the time's place; a pinned row wears a white pin there. The last one
/// copied has the cursor fill; just copied, a white ✓ for 1.5 s instead of
/// the time. No card, no plate.
///
/// A picture is a 44 pt row (two pitches, so both columns stay on the 22 pt
/// grid) with a 56 × 36 thumbnail of its whole shape and «Картинка» over its
/// size: a 20 × 12 one did not tell one screenshot from another (owner,
/// 22.10). The pointer resting on it opens a larger preview beside the island.
struct ClipboardRow: View {
    let item: ClipboardItem
    var number: Int? = nil
    var commandHeld = false
    var isPinned = false
    var showsTools = false
    var isSelected = false
    var justCopied = false
    /// Where a picture's preview opens: past the column's outer edge.
    var previewEdge: Edge = .trailing

    static let toolFont = Font.system(size: 12, weight: .medium)
    static let toolBox: CGFloat = 18
    static let toolGap: CGFloat = 4
    /// Pin and ×.
    static let toolsWidth: CGFloat = toolBox * 2 + toolGap
    static let numberWidth: CGFloat = 20
    static let iconSide: CGFloat = 12
    static let pictureRowHeight: CGFloat = DSE.Size.rowPitch * 2
    static let pictureThumbnail = CGSize(width: 56, height: 36)
    static let pictureRadius: CGFloat = 4
    /// How long the pointer rests on a picture before its preview opens:
    /// passing over the list opens nothing.
    static let previewDelay: Duration = .milliseconds(400)

    @State private var thumbnail: ClipboardThumbnails.Thumbnail?
    /// Where the row is on screen, for the preview's own window.
    @State private var anchor = ScreenAnchorBox()
    @Environment(\.colorSchemeContrast) private var contrast

    private var isPicture: Bool { item.type == .image }

    var body: some View {
        HStack(spacing: 0) {
            numberLabel
                .frame(width: Self.numberWidth, alignment: .leading)
            SourceAppIcon(bundleID: item.sourceBundleID, side: Self.iconSide)
                .padding(.trailing, 6)
            if isPicture {
                pictureThumbnail
                    .padding(.trailing, 8)
                pictureLabel
            } else {
                if let swatch = colourSwatch {
                    swatch.padding(.trailing, 6)
                }
                Text(verbatim: ClipboardRowText.title(for: item))
                    .eText(.body)
                    .foregroundStyle(DSE.Palette.text)
                    .lineLimit(1)
                    .truncationMode(ClipboardRowText.truncation(for: item.type))
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(height: isPicture ? Self.pictureRowHeight : DSE.Size.rowPitch)
        .cursorFill(isSelected || justCopied)
        .contentShape(Rectangle())
        .background { if isPicture { ScreenAnchor(box: anchor) } }
        .task(id: item.id) {
            // A small copy, decoded once per entry off the main thread: the
            // list is lazy and rows come back with every scroll.
            guard isPicture else { thumbnail = nil; return }
            thumbnail = ClipboardThumbnails.cached(item.id)
            if thumbnail == nil { thumbnail = await ClipboardThumbnails.load(for: item) }
        }
        // Only the pointer resting on a picture decodes its preview: nothing
        // runs while idle.
        .task(id: isPicture && showsTools) { await showPreviewAfterRest() }
        .onDisappear { ClipboardPreviewPanel.shared.hide(owner: item.id) }
        // Built here, where the thumbnail lands: the list does not redraw
        // when it does, so a label made there missed the size.
        .modifier(ClipboardRowLabel(text: isPicture
            ? ClipboardRowText.accessibilityLabel(for: item, pixelSize: thumbnail?.pixelSize)
            : nil))
    }

    /// The pointer rested on a picture: its preview opens in a window of its
    /// own that never takes the keyboard or a click (a popover became key and
    /// took ⌘N, the arrows and Esc from «Буфер»). The pointer leaving drops
    /// the preview and its picture.
    private func showPreviewAfterRest() async {
        guard isPicture, showsTools else {
            ClipboardPreviewPanel.shared.hide(owner: item.id)
            return
        }
        try? await Task.sleep(for: Self.previewDelay)
        guard !Task.isCancelled, let preview = await ClipboardThumbnails.loadPreview(for: item), !Task.isCancelled,
              let window = anchor.view?.window, let rect = anchor.screenRect
        else { return }
        ClipboardPreviewPanel.shared.show(
            ClipboardPicturePreview(
                thumbnail: preview,
                caption: preview.pixelSize.map(ClipboardRowText.pictureTitle) ?? String(localized: "Picture"),
                origin: ClipboardRowText.origin(for: item)
            ),
            owner: item.id,
            beside: rect,
            edge: previewEdge,
            over: window
        )
    }

    /// The picture's whole shape on the placeholder, 56 × 36.
    private var pictureThumbnail: some View {
        ZStack {
            DSE.Palette.placeholder
            if let thumbnail {
                Image(decorative: thumbnail.image, scale: 2)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(DSE.Palette.tertiary(contrast))
            }
        }
        .frame(width: Self.pictureThumbnail.width, height: Self.pictureThumbnail.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.pictureRadius, style: .continuous))
        .hairlineRim(cornerRadius: Self.pictureRadius)
        .accessibilityHidden(true)
    }

    /// «Картинка» over «3456 × 2234».
    private var pictureLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: String(localized: "Picture"))
                .eText(.body)
                .foregroundStyle(DSE.Palette.text)
                .lineLimit(1)
            if let size = thumbnail?.pixelSize {
                Text(verbatim: ClipboardRowText.pixelSize(size))
                    .eText(.time)
                    .foregroundStyle(DSE.Palette.tertiary(contrast))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var numberLabel: some View {
        if let number {
            Text(verbatim: commandHeld ? "⌘\(number)" : "\(number)")
                .eText(.time)
                .foregroundStyle(commandHeld ? DSE.Palette.text : DSE.Palette.tertiary(contrast))
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// A colour's swatch; nothing for the rest.
    private var colourSwatch: AnyView? {
        if let rgb = ClipboardRowText.swatch(item.type == .url ? nil : item.stringData) {
            return AnyView(
                Circle()
                    .fill(Color(rgb: rgb))
                    .overlay(Circle().strokeBorder(DSE.Palette.edge(contrast), lineWidth: DSE.Line.hairline))
                    .frame(width: 10, height: 10)
            )
        }
        return nil
    }

    @ViewBuilder
    private var trailing: some View {
        if showsTools {
            Color.clear.frame(width: Self.toolsWidth, height: 1)
        } else if justCopied {
            Image(systemName: "checkmark")
                .font(Self.toolFont)
                .foregroundStyle(DSE.Palette.text)
                .frame(width: Self.toolBox)
                .accessibilityLabel(Text("Copied"))
        } else if isPinned {
            Color.clear.frame(width: Self.toolBox, height: 1)
        } else {
            Text(verbatim: DayTimeLabel.compact(for: item.timestamp))
                .eText(.time)
                .foregroundStyle(DSE.Palette.tertiary(contrast))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// A picture row's 56 × 36 thumbnail (at 2×), its hover preview and the
/// picture's pixel size, for «Картинка · 1920 × 1080». Made from the file by
/// ImageIO off the main thread, never a full decode, and kept per entry.
enum ClipboardThumbnails {
    struct Thumbnail: @unchecked Sendable {
        let image: CGImage
        let pixelSize: CGSize?
    }

    /// Twice the 56 pt the row shows.
    static let maxPixelSide = 112
    /// Twice the longest side the hover preview shows.
    static let previewPixelSide = Int(max(ClipboardPicturePreview.width, ClipboardPicturePreview.maxHeight) * 2)

    private final class Box {
        let value: Thumbnail
        init(_ value: Thumbnail) { self.value = value }
    }

    private static let cache: NSCache<NSUUID, Box> = {
        let cache = NSCache<NSUUID, Box>()
        cache.countLimit = 300
        cache.totalCostLimit = 8 << 20
        return cache
    }()

    /// The preview on screen: one is looked at a time, and it goes when the
    /// preview hides.
    private static let previews: NSCache<NSUUID, Box> = {
        let cache = NSCache<NSUUID, Box>()
        cache.countLimit = 4
        return cache
    }()

    static func cached(_ id: UUID) -> Thumbnail? {
        cache.object(forKey: id as NSUUID)?.value
    }

    static func load(for item: ClipboardItem) async -> Thumbnail? {
        if let hit = cached(item.id) { return hit }
        let made = await decode(item, maxPixelSide: maxPixelSide, priority: .utility)
        if let made { cache.setObject(Box(made), forKey: item.id as NSUUID, cost: made.image.bytesPerRow * made.image.height) }
        return made
    }

    /// The previews kept go once none is shown (`ClipboardPreviewPanel.hide`).
    static func dropPreviews() {
        previews.removeAllObjects()
    }

    /// The preview under the pointer; decoded only then.
    static func loadPreview(for item: ClipboardItem) async -> Thumbnail? {
        if let hit = previews.object(forKey: item.id as NSUUID)?.value { return hit }
        let made = await decode(item, maxPixelSide: previewPixelSide, priority: .userInitiated)
        if let made { previews.setObject(Box(made), forKey: item.id as NSUUID) }
        return made
    }

    private static func decode(_ item: ClipboardItem, maxPixelSide: Int, priority: TaskPriority) async -> Thumbnail? {
        let inMemory = ClipboardItem.inMemoryImage(for: item.id)
        let file = item.imageFileName.map { ClipboardManager.clipboardDataDirectory.appendingPathComponent($0) }
        return await Task.detached(priority: priority) { () -> Thumbnail? in
            if let inMemory { return make(from: CGImageSourceCreateWithData(inMemory as CFData, nil), maxPixelSide: maxPixelSide) }
            guard let file else { return nil }
            return make(from: CGImageSourceCreateWithURL(file as CFURL, nil), maxPixelSide: maxPixelSide)
        }.value
    }

    static func make(from data: Data, maxPixelSide: Int = maxPixelSide) -> Thumbnail? {
        make(from: CGImageSourceCreateWithData(data as CFData, nil), maxPixelSide: maxPixelSide)
    }

    private static func make(from source: CGImageSource?, maxPixelSide: Int = maxPixelSide) -> Thumbnail? {
        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var size: CGSize?
        if let width = properties?[kCGImagePropertyPixelWidth] as? Int, let height = properties?[kCGImagePropertyPixelHeight] as? Int,
           width > 0, height > 0 {
            size = CGSize(width: width, height: height)
        }
        return Thumbnail(image: image, pixelSize: size)
    }
}

/// A picture row's preview while the pointer rests on it: the whole picture,
/// at most 260 × 300 and never past its own size at 2×, on the island's
/// black, then its size and where it came from. About 280 pt wide.
struct ClipboardPicturePreview: View {
    let thumbnail: ClipboardThumbnails.Thumbnail
    let caption: String
    let origin: String

    static let width: CGFloat = 260
    static let maxHeight: CGFloat = 300
    static let inset: CGFloat = 10
    static let radius: CGFloat = 12

    @Environment(\.colorSchemeContrast) private var contrast

    /// The picture's shape fitted into 260 × 300, at most half its pixels.
    static func size(for pixels: CGSize) -> CGSize {
        guard pixels.width > 0, pixels.height > 0 else { return CGSize(width: width, height: (width * 10 / 16).rounded()) }
        let scale = min(width / pixels.width, maxHeight / pixels.height, 0.5)
        return CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
    }

    var body: some View {
        let pixels = thumbnail.pixelSize ?? CGSize(width: thumbnail.image.width, height: thumbnail.image.height)
        let size = Self.size(for: pixels)
        VStack(alignment: .leading, spacing: 8) {
            Image(decorative: thumbnail.image, scale: 2)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: ClipboardRow.pictureRadius, style: .continuous))
                .hairlineRim(cornerRadius: ClipboardRow.pictureRadius)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: caption)
                    .eText(.caption)
                    .foregroundStyle(DSE.Palette.text)
                Text(verbatim: origin)
                    .eText(.time)
                    .foregroundStyle(DSE.Palette.tertiary(contrast))
            }
            .lineLimit(1)
        }
        .frame(width: Self.width)
        .padding(Self.inset)
        .background(DSE.Palette.island)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .hairlineRim(cornerRadius: Self.radius)
        .accessibilityHidden(true)
    }
}

/// The hover preview's own window: borderless, non-activating, never key or
/// main, and deaf to the pointer, so the island keeps the keyboard and a
/// click lands on the row under it. One for the app; it hangs one level
/// above the island and is shared on screen exactly as the island is.
@MainActor
final class ClipboardPreviewPanel {
    static let shared = ClipboardPreviewPanel()

    /// Between the row and the preview.
    nonisolated static let gap: CGFloat = 8

    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var owner: UUID?

    /// The size `content` asks for, from a hosting view with its default
    /// sizing that is never put in a window.
    static func measuredSize<Content: View>(of content: Content) -> CGSize {
        NSHostingView(rootView: content).fittingSize
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Where the preview goes: past `anchor`'s `edge`, centred on it, kept
    /// on `screen`.
    nonisolated static func frame(size: CGSize, beside anchor: CGRect, edge: Edge, screen: CGRect) -> CGRect {
        var x = edge == .leading ? anchor.minX - gap - size.width : anchor.maxX + gap
        var y = anchor.midY - size.height / 2
        x = min(max(x, screen.minX), max(screen.minX, screen.maxX - size.width))
        y = min(max(y, screen.minY), max(screen.minY, screen.maxY - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    func show<Content: View>(_ content: Content, owner: UUID, beside anchor: CGRect, edge: Edge, over window: NSWindow) {
        let panel = self.panel ?? makePanel()
        let hosting = self.hosting ?? NSHostingView(rootView: AnyView(EmptyView()))
        if self.hosting == nil {
            hosting.translatesAutoresizingMaskIntoConstraints = true
            // The panel is sized here, from fittingSize. Left to its defaults the
            // hosting view also drives the window's min/max size, and a picture
            // that finishes loading mid-layout re-entered Update Constraints
            // until AppKit threw (crash, 1.1.1, 23.10).
            hosting.sizingOptions = []
            panel.setSelfSizedContent(hosting)
            self.hosting = hosting
        }
        hosting.rootView = AnyView(content)
        // With sizingOptions = [] the shown hosting view's fittingSize is
        // zero, and the preview was an empty 0 × 0 panel since 1.1.2: it is
        // measured on a hosting view of its own, outside any window.
        let size = Self.measuredSize(of: content)
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(origin: .zero, size: size)
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        panel.sharingType = window.sharingType
        panel.setFrame(Self.frame(size: size, beside: anchor, edge: edge, screen: screen), display: true)
        self.owner = owner
        // Shown without activating Skerry or taking the key window.
        panel.orderFrontRegardless()
    }

    /// Hides the preview `owner` opened; another row's preview stays.
    func hide(owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        panel?.orderOut(nil)
        // Let the decoded picture go with it, from the cache too.
        hosting?.rootView = AnyView(EmptyView())
        ClipboardThumbnails.dropPreviews()
    }

    private func makePanel() -> NSPanel {
        let panel = Panel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

/// Hands its NSView to `box`, so a SwiftUI row can find itself on screen.
struct ScreenAnchor: NSViewRepresentable {
    let box: ScreenAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}

final class ScreenAnchorBox {
    weak var view: NSView?

    /// The view's bounds in screen coordinates, once it is in a window.
    var screenRect: CGRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

/// A row's VoiceOver label, when it has one of its own; nil leaves the
/// row's children to speak.
struct ClipboardRowLabel: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: text))
        } else {
            content
        }
    }
}

/// Where a removed row was: «Запись удалена» and «Отменить» for 5 s.
struct RemovedClipboardRow: View {
    let onUndo: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundStyle(DSE.Palette.tertiary(contrast))
                .frame(width: ClipboardRow.numberWidth, alignment: .leading)
                .accessibilityHidden(true)
            Text("Item deleted")
                .eText(.body)
                .foregroundStyle(DSE.Palette.secondary(contrast))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text("Undo")
                    .eText(.bodyEmphasis)
                    .foregroundStyle(DSE.Palette.text)
                    .frame(height: DSE.Size.rowPitch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressDimStyle())
        }
        .frame(height: DSE.Size.rowPitch)
        .accessibilityElement(children: .contain)
    }
}

/// What a clipboard row says and shows.
enum ClipboardRowText {
    /// Two columns of 273 with this between them in the 570 content.
    static let gutter: CGFloat = 24

    /// Newest first down the left column, then the right: the left takes the
    /// odd one.
    static func leftColumnCount(_ count: Int) -> Int { (count + 1) / 2 }

    /// "github.com/apple/swift", "report.pdf", "3 files · a.png, b.png", the
    /// text on one line.
    static func title(for item: ClipboardItem) -> String {
        switch item.type {
        case .url:
            let link = ClipboardCardText.link(item.stringData ?? item.preview)
            return link.host + link.rest
        case .file:
            let names = (item.fileURLs ?? []).compactMap { URL(string: $0)?.lastPathComponent }
            let title = ClipboardCardText.fileTitle(names: names)
            return names.count > 1 ? "\(title) · \(names.joined(separator: ", "))" : title
        case .image:
            return String(localized: "Picture")
        case .text, .rtf, .unknown:
            return oneLine(item.stringData ?? item.preview)
        }
    }

    /// «Картинка · 1920 × 1080».
    static func pictureTitle(_ size: CGSize) -> String {
        "\(String(localized: "Picture")) · \(pixelSize(size))"
    }

    /// «1920 × 1080».
    static func pixelSize(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height))"
    }

    /// Lines joined by spaces; only the start of a long text is looked at.
    static func oneLine(_ text: String) -> String {
        text.prefix(400)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The whole entry under the pointer: where it came from and when, then
    /// its text (the row shows one line of it).
    static func tooltip(for item: ClipboardItem, now: Date = Date()) -> String {
        let head = origin(for: item, now: now)
        let body: String
        switch item.type {
        case .text, .rtf, .unknown, .url: body = String((item.stringData ?? item.preview).prefix(600))
        case .file: body = (item.fileURLs ?? []).compactMap { URL(string: $0)?.lastPathComponent }.joined(separator: "\n")
        case .image: body = String(localized: "Picture")
        }
        return "\(head)\n\(body)"
    }

    /// What VoiceOver reads for a row. A picture has no tooltip and its
    /// preview is not reachable from the keyboard, so its label says where it
    /// came from and when: «Картинка · 1920 × 1080, Safari · Сегодня, 10:42».
    static func accessibilityLabel(for item: ClipboardItem, pixelSize: CGSize? = nil, now: Date = Date()) -> String {
        guard item.type == .image else { return "\(item.type.displayName): \(item.preview)" }
        let size = pixelSize ?? ClipboardThumbnails.cached(item.id)?.pixelSize
        let title = size.map(pictureTitle) ?? String(localized: "Picture")
        return "\(title), \(origin(for: item, now: now))"
    }

    /// «Safari · Сегодня, 10:42»: where the entry came from and when.
    static func origin(for item: ClipboardItem, now: Date = Date()) -> String {
        let when = DayTimeLabel.make(for: item.timestamp, now: now)
        guard let id = item.sourceBundleID, let name = SourceApps.name(for: id) else { return when }
        return "\(name) · \(when)"
    }

    /// Links and file names keep their ends («github.com/…/pull/42»,
    /// «Отчёт_окт…_v2.pdf»); text keeps its start.
    static func truncation(for type: ClipboardItemType) -> Text.TruncationMode {
        type == .url || type == .file ? .middle : .tail
    }

    /// "#5BBEEB" (the whole entry) is a colour: shown with a swatch.
    static func swatch(_ text: String?) -> UInt32? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 7, trimmed.first == "#" else { return nil }
        let hex = trimmed.dropFirst()
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(hex, radix: 16)
    }
}

/// The apps copies came from, looked up once per app: rows re-render with
/// the pointer, the workspace is not asked again.
enum SourceApps {
    private static let icons = NSCache<NSString, NSImage>()
    private static let names = NSCache<NSString, NSString>()
    private static let missingIcon = NSImage()

    static func icon(for bundleID: String) -> NSImage? {
        if let hit = icons.object(forKey: bundleID as NSString) { return hit === missingIcon ? nil : hit }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons.setObject(icon ?? missingIcon, forKey: bundleID as NSString)
        return icon
    }

    static func name(for bundleID: String) -> String? {
        if let hit = names.object(forKey: bundleID as NSString) { return hit.length == 0 ? nil : hit as String }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) }
        names.setObject((name ?? "") as NSString, forKey: bundleID as NSString)
        return name
    }
}

/// Icon of the app a copy came from.
private struct SourceAppIcon: View {
    let bundleID: String?
    var side: CGFloat = 14

    var body: some View {
        if let bundleID, let icon = SourceApps.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .help(SourceApps.name(for: bundleID) ?? "")
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: side - 3))
                .foregroundStyle(.secondary)
                .frame(width: side, height: side)
        }
    }
}

// MARK: - AppKit input

/// Clicks, double-clicks, drags and keys for a clipboard card.
private struct ClipboardCardInteraction: NSViewRepresentable {
    let writers: () -> [NSPasteboardWriting]
    let dragImage: () -> NSImage?
    /// The row's whole text (a row shows one line of it).
    var tooltip: String? = nil
    let onClick: () -> Void
    let onDoubleClick: (_ shift: Bool) -> Void
    let onDragChanged: (Bool) -> Void
    let onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ClipboardCardInteractionView { update(ClipboardCardInteractionView()) }
    func updateNSView(_ view: ClipboardCardInteractionView, context: Context) { _ = update(view) }

    private func update(_ view: ClipboardCardInteractionView) -> ClipboardCardInteractionView {
        view.writers = writers
        view.dragImage = dragImage
        if view.toolTip != tooltip { view.toolTip = tooltip }
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onDragChanged = onDragChanged
        view.onKey = onKey
        return view
    }
}

final class ClipboardCardInteractionView: NSView, NSDraggingSource {
    var writers: (() -> [NSPasteboardWriting])?
    var dragImage: (() -> NSImage?)?
    var onClick: (() -> Void)?
    var onDoubleClick: ((Bool) -> Void)?
    var onDragChanged: ((Bool) -> Void)?
    var onKey: ((NSEvent) -> Bool)?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let start = mouseDownEvent else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x,
                             event.locationInWindow.y - start.locationInWindow.y)
        guard distance >= 3, let writers = writers?(), !writers.isEmpty else { return }
        didStartDrag = true
        // A picture drags as itself, not as a document icon.
        let picture = dragImage?()
        let image = picture ?? NSWorkspace.shared.icon(for: .data)
        let size = picture.map { ClipboardDragPreview.size(for: $0.size) } ?? NSSize(width: 32, height: 32)
        let items = writers.enumerated().map { index, writer -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: writer)
            let offset = CGFloat(min(index, 4)) * 6
            item.setDraggingFrame(NSRect(x: offset, y: -offset, width: size.width, height: size.height), contents: image)
            return item
        }
        beginDraggingSession(with: items, event: start, source: self).draggingFormation = .pile
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !didStartDrag else { return }
        if event.clickCount >= 2 {
            onDoubleClick?(event.modifierFlags.contains(.shift))
        } else {
            onClick?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, onKey?(event) == true else { return super.performKeyEquivalent(with: event) }
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    /// Copy whatever keys are held: with ⌘ or ⌃ down the copy-only mask would
    /// otherwise become empty and every destination would refuse the drop.
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { onDragChanged?(true) }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragChanged?(false)
    }
}

/// What the clipboard cards say about files and links.
enum ClipboardCardText {
    /// "report.pdf", or "3 files".
    static func fileTitle(names: [String]) -> String {
        if names.count == 1 { return names[0] }
        return String(format: String(localized: "%lld files"), names.count)
    }

    /// A link as its site and the rest: "github.com" and "/apple/swift".
    static func link(_ string: String) -> (host: String, rest: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let host = components.host, !host.isEmpty else {
            return (trimmed, "")
        }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var rest = components.percentEncodedPath.removingPercentEncoding ?? components.path
        if rest == "/" { rest = "" }
        if let query = components.query, !query.isEmpty { rest += "?" + query }
        return (site, rest)
    }
}

/// The size a picture is dragged at: its shape, at most 120 pt across.
enum ClipboardDragPreview {
    static func size(for image: CGSize) -> NSSize {
        guard image.width > 0, image.height > 0 else { return NSSize(width: 32, height: 32) }
        let scale = min(1, 120 / max(image.width, image.height))
        return NSSize(width: (image.width * scale).rounded(), height: (image.height * scale).rounded())
    }
}
