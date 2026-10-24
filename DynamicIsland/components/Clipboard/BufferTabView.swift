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
import SwiftUI

/// The Clipboard tab, now with the screenshots in it (docs/PLAN-DESIGN.md
/// §3.4). Buffer v3 (docs/design/mockups/E/Buffer-v3.dc.html): no plate
/// anywhere. First the filters as words — ВСЕ · СНИМКИ · ТЕКСТ · ССЫЛКИ ·
/// ФАЙЛЫ — with the pinned count, search and pause on the right, over a
/// hairline; then, in «Все», the latest batch as a film with its action row
/// and the one lit key «Вставить в Claude · N»; then the copies as two
/// columns of numbered rows.
struct BufferTabView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var state = BufferTabState.shared
    @ObservedObject private var screenshots = ScreenshotShelfManager.shared
    @ObservedObject private var clipboard = ClipboardManager.shared
    @ObservedObject private var presentation = ScreenPresentation.shared
    @StateObject private var quickLook = QuickLookService()
    @Default(.enableScreenshotShelf) private var screenshotsOn
    @Default(.enableClipboardManager) private var clipboardOn
    @Default(.clipboardDisplayMode) private var clipboardMode
    @Default(.clipboardHistoryPaused) private var paused
    @Default(.screenshotThumbnailSize) private var thumbnailWidth
    @State private var typesShown = false
    @State private var typesToken = UUID()
    @State private var trashToken = UUID()
    @State private var folderToken = UUID()
    /// «Сохранять в ~/Screenshots» asks first, as in Settings: it changes a
    /// macOS setting and restarts the menu bar for a moment.
    @State private var confirmsShotsFolder = false
    @FocusState private var searchFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var available: [BufferSegment] {
        BufferSegment.available(clipboard: clipboardOn && clipboardMode == .notchTab, screenshots: screenshotsOn)
    }

    private var segment: BufferSegment? {
        BufferSegment.resolve(state.segment, available: available)
    }

    /// What the trash would take on the filter shown.
    private var clearableCount: Int {
        BufferTabState.clearableCount(segment, history: clipboard.clipboardHistory, shownShots: screenshotsOn ? screenshots.shownItemIDs.count : 0)
    }

    /// The latest batch while it sits on top of the copies.
    private var latestBatch: ScreenshotBatch? {
        guard let batch = screenshots.store.batches.first, let segment,
              BufferLayout.showsBatchStrip(segment: segment, lastAddedAt: batch.lastAddedAt, now: Date())
        else { return nil }
        return batch
    }

    /// Toasts come and go by opacity (M10).
    static let fade = Animation.easeOut(duration: 0.2)

    private var searching: Bool { state.searching }

    var body: some View {
        if presentation.isHidingContent {
            // One grey line; the tabs and «…» stay (Buffer v3, state 12).
            VStack(spacing: 0) {
                NoticeRow(
                    symbol: "eye.slash",
                    title: String(localized: "Hidden while your screen is shared or recorded."),
                    centered: true
                )
                .padding(.top, 8)
                BufferSlackFiller()
            }
            .padding(.horizontal, Self.inset)
            .modifier(BufferTabFrame())
            .onPreferenceChange(BufferSlackKey.self) { slack in
                MainActor.assumeIsolated { state.fit(slack: slack) }
            }
        } else {
            let batch = latestBatch
            VStack(alignment: .leading, spacing: 0) {
                if available.count > 1 {
                    filterRow
                    Hairline()
                        .padding(.top, 6)
                        .padding(.bottom, 6)
                }
                if let batch {
                    LatestBatchStrip(batch: batch, quickLook: quickLook) { choose(.screenshots) }
                        .padding(.bottom, 16)
                }
                content(batch: batch)
            }
            .onPreferenceChange(BufferSlackKey.self) { slack in
                MainActor.assumeIsolated { state.fit(slack: slack) }
            }
            // Gone files and a moved folder are looked for when the tab is
            // looked at, not on a timer.
            .onAppear { screenshots.refreshOnLook() }
            .padding(.horizontal, Self.inset)
            .padding(.top, 6)
            .modifier(BufferTabFrame())
            // With the batch on top, its action row shows a short toast
            // (VISUAL-E §2.9); a warning, and any toast without the batch,
            // is one capsule over the content (Q24), two lines when long.
            // The history's «Отменить» rides a capsule too when the history
            // is not on screen (moved to «Снимки» during the offer).
            .overlay(alignment: .top) {
                VStack(spacing: 6) {
                    if BufferLayout.clearedUndoNeedsCapsule(segment: segment, undo: state.undo?.kind), let undo = state.undo {
                        ToastCapsule(
                            symbol: "trash",
                            message: BufferUndo.clearedMessage(undo.count),
                            actionTitle: String(localized: "Undo"),
                            action: { state.undoRemoval() }
                        )
                        .transition(.opacity)
                    }
                    if let toast = state.toast, batch == nil || state.toastIsWarning {
                        ToastCapsule(
                            symbol: state.toastIsWarning ? "exclamationmark.circle" : "checkmark",
                            tint: state.toastIsWarning ? DS.Palette.attention : DSE.Palette.text,
                            message: toast,
                            lineLimit: 2
                        )
                        .help(toast)
                        .transition(.opacity)
                    }
                }
                .padding(.top, 34)
            }
            .animation(Self.fade, value: state.toast)
            .animation(Self.fade, value: state.undo?.id)
            .quickLookPresenter(using: quickLook)
            // Files are not history: the Trash keeps its question (board, row 41).
            .alert("Move to the Trash?", isPresented: Binding(
                get: { screenshots.pendingRemoval != nil },
                set: { if !$0 { screenshots.pendingRemoval = nil } }
            )) {
                Button("Move to Trash", role: .destructive) { screenshots.confirmPendingRemoval() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(String(format: String(localized: "%lld screenshot files go to the Trash: “Move originals to the Trash” is on in Screenshots settings."), screenshots.pendingRemoval?.count ?? 0))
            }
            .onChange(of: screenshots.pendingRemoval) { _, pending in
                vm.setAutoCloseSuppression(pending != nil, token: trashToken)
            }
            .alert("Save screenshots to ~/Screenshots?", isPresented: $confirmsShotsFolder) {
                Button("Use ~/Screenshots") { screenshots.useRecommendedFolder() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(String(format: String(localized: "This creates %@, tells macOS to save screenshots there and restarts the menu bar for a moment. Existing screenshots are not moved."),
                            ScreenshotLocation.recommendedFolder().path))
            }
            .onChange(of: confirmsShotsFolder) { _, shown in
                vm.setAutoCloseSuppression(shown, token: folderToken)
            }
            .onChange(of: typesShown) { _, shown in
                vm.setAutoCloseSuppression(shown, token: typesToken)
            }
            .onDisappear {
                vm.setAutoCloseSuppression(false, token: typesToken)
                vm.setAutoCloseSuppression(false, token: folderToken)
                // The island closed (↩ pasted the first find, say) or the tab
                // changed: no query is left to filter the next opening.
                state.tabDisappeared()
            }
        }
    }

    /// The content's inset: with the island's own 14 it starts under the
    /// first tab word.
    static let inset: CGFloat = DS.Space.s

    /// A click on Screenshots is the person asking for them: only then is
    /// their folder looked at, on a fresh install (§5.8). Not when the tab
    /// merely shows that segment: with the clipboard off it is the only one,
    /// and a hover over the island would have brought up the macOS prompt.
    private func choose(_ chosen: BufferSegment) {
        state.segment = chosen
        if chosen == .screenshots { screenshots.startOnFirstUse() }
    }

    // MARK: Filters, pinned, search, pause, thumbnail size

    /// The first content row: the filters as words (or the search field in
    /// their place) and, on the right, the pinned count, the magnifier and
    /// pause — in «Снимки» the thumbnail size instead of pins and search.
    private var filterRow: some View {
        HStack(spacing: 4) {
            if searching {
                searchField
            } else {
                FilterWords<BufferSegment>(
                    items: available.map { FilterWords<BufferSegment>.Item(id: $0, title: $0.title) },
                    selection: segment
                ) { choose($0) }
                Spacer(minLength: 8)
            }
            if segment == .screenshots {
                Image(systemName: "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(DSE.Palette.tertiary(contrast))
                    .accessibilityHidden(true)
                StepLine(
                    steps: ScreenshotGridLayout.sizeSteps.count,
                    selected: ScreenshotGridLayout.sizeStep(for: thumbnailWidth),
                    label: String(localized: "Thumbnail size")
                ) { step in
                    thumbnailWidth = ScreenshotGridLayout.sizeSteps[step]
                }
                .padding(.trailing, 4)
            } else if clipboardOn {
                pinnedToggle
                if !searching {
                    GlyphButton(symbol: "magnifyingglass", label: String(localized: "Search"),
                                font: Self.glyph, box: Self.glyphBox) {
                        openSearch()
                    }
                }
            }
            // The trash: what the filter shows goes, with «Отменить» (23.10).
            // Not while searching: it would take the whole filter, not the finds.
            if clearableCount > 0, !presentation.isHidingContent, !searching, let segment {
                GlyphButton(symbol: "trash", label: String(localized: "Clear"), font: Self.glyph, box: Self.glyphBox) {
                    state.clear(segment)
                }
            }
            if clipboardOn {
                GlyphButton(
                    symbol: paused ? "play.fill" : "pause.fill",
                    label: paused ? String(localized: "Resume clipboard history") : String(localized: "Pause clipboard history"),
                    font: Self.glyph, box: Self.glyphBox,
                    tint: paused ? DS.Palette.paused : nil
                ) {
                    paused.toggle()
                }
            }
        }
        .frame(height: Self.glyphBox)
        // «Снимки» has no search: the field closes when the filter moves there.
        .onChange(of: segment) { _, now in
            if now == .screenshots && searching { closeSearch() }
        }
    }

    static let glyph = Font.system(size: 12, weight: .medium)
    static let glyphBox: CGFloat = 22

    /// The pin with the number of pinned entries: a click shows or folds
    /// them over «Недавнее»; white while they show. Not there while nothing
    /// is pinned.
    @ViewBuilder
    private var pinnedToggle: some View {
        if !clipboard.pinnedItems.isEmpty {
            let open = state.showsPinned || !state.query.isEmpty
            let count = ClipboardFiltering.apply(clipboard.pinnedItems, filter: segment?.clipboardFilter ?? .all, query: state.query).count
            Button {
                withAnimation(DS.spring) { state.showsPinned.toggle() }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: open ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .medium))
                    Text(verbatim: "\(count)")
                        .eText(.time)
                }
                .foregroundStyle(open ? DSE.Palette.text : DSE.Palette.secondary(contrast))
                .padding(.horizontal, 4)
                .frame(height: Self.glyphBox)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressDimStyle())
            .help(open ? String(localized: "Hide pinned") : String(localized: "Show pinned"))
            .accessibilityLabel(Text(open ? "Hide pinned" : "Show pinned"))
            .accessibilityValue(Text(verbatim: "\(count)"))
        }
    }

    private func openSearch() {
        withAnimation(DS.spring) { state.openSearch() }
        DispatchQueue.main.async { searchFocused = true }
    }

    private func closeSearch() {
        withAnimation(DS.spring) { state.closeSearch() }
    }

    /// The field takes the words' place, on the same hairline, no capsule:
    /// the magnifier, the query, the type as a word («Все типы ˅», changed
    /// without leaving the search) and ×, which clears the query or, empty,
    /// closes the field. Esc closes it too; Return pastes the first find.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Self.glyph)
                .foregroundStyle(DSE.Palette.tertiary(contrast))
                .accessibilityHidden(true)
            TextField(String(localized: "Search"), text: $state.query)
                .textFieldStyle(.plain)
                .font(DSE.Typeface.body)
                .foregroundStyle(DSE.Palette.text)
                .focused($searchFocused)
                .onSubmit { state.submitSearch(plainText: NSEvent.modifierFlags.contains(.shift)) }
                .onExitCommand { closeSearch() }
            typePicker
            GlyphButton(symbol: "xmark", label: String(localized: "Clear search"),
                        font: Self.glyph, box: Self.glyphBox) {
                if state.query.isEmpty { closeSearch() } else { state.query = "" }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The filters while searching: «Все типы», «Текст», «Ссылки», «Файлы».
    private var typePicker: some View {
        let types = available.filter { $0 != .screenshots }
        let current = segment ?? .all
        return Button {
            typesShown.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(current == .all ? String(localized: "All types") : current.title)
                    .eText(.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(typesShown ? DSE.Palette.text : DSE.Palette.secondary(contrast))
            .frame(height: Self.glyphBox)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .fixedSize()
        .popover(isPresented: $typesShown, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                ForEach(types) { type in
                    MoreMenuRow(
                        title: type == .all ? String(localized: "All types") : type.title,
                        trailing: type == current ? "✓" : nil,
                        opensPanel: false
                    ) {
                        typesShown = false
                        choose(type)
                    }
                }
            }
            .padding(4)
            .frame(width: 200)
            .background(DSE.Palette.island)
            .presentationBackground(DSE.Palette.island)
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(batch: ScreenshotBatch?) -> some View {
        switch segment {
        case .screenshots:
            screenshotsContent
        case .none:
            VStack(spacing: 0) {
                NoticeRow(
                    symbol: "doc.on.clipboard",
                    title: String(localized: "Clipboard is off"),
                    message: String(localized: "Turn on the clipboard or screenshot collecting in Settings."),
                    centered: true
                )
                .padding(.top, 8)
                BufferSlackFiller()
            }
        default:
            NotchClipboardView(embedded: true, onOtherKey: otherKeys(batch: batch))
        }
    }

    /// The latest batch's keys (space, ⌘A, ⌘C, Delete) work in «Все» as soon
    /// as the island opens with a shortcut, before a frame is clicked.
    private func otherKeys(batch: ScreenshotBatch?) -> ((NSEvent) -> Bool)? {
        guard let batch else { return nil }
        let quickLook = quickLook
        return { event in
            guard let command = ScreenshotGridCommand(event: event), command != .clearSelection else { return false }
            if command == .removeSelected, ScreenshotShelfManager.shared.selectedCount(in: batch) == 0 { return false }
            LatestBatchStrip.run(command, batch: batch, quickLook: quickLook)
            return true
        }
    }

    @ViewBuilder
    private var screenshotsContent: some View {
        if !screenshots.canReadFolder {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    NoticeRow(
                        symbol: "lock",
                        title: String(localized: "No access to the screenshot folder"),
                        message: String(format: String(localized: "needs access to the “%@” folder"),
                                        FileManager.default.displayName(atPath: screenshots.folder.path)),
                        actionTitle: String(localized: "Allow…"),
                        action: openFolderPrivacySettings
                    )
                    // The other way out: a folder macOS does not guard.
                    if screenshots.folder.standardizedFileURL != ScreenshotLocation.recommendedFolder().standardizedFileURL {
                        Button {
                            confirmsShotsFolder = true
                        } label: {
                            Text("Save to ~/Screenshots")
                                .eText(.caption)
                                .foregroundStyle(DSE.Palette.secondary(contrast))
                                .underline()
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 4)
                                .frame(height: DSE.Size.key)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressDimStyle())
                        .help(String(localized: "Save screenshots to ~/Screenshots?"))
                    }
                }
                .help(String(localized: "macOS keeps Skerry out of this folder. Choose ~/Screenshots in Screenshots settings, or allow access in System Settings."))
                Hairline()
                if ScreenshotBatchPanel.visibleBatches(screenshots.store.batches, onlyClipboardShots: true).isEmpty {
                    noScreenshotsYet.padding(.top, 8)
                    BufferSlackFiller()
                } else {
                    // Clipboard screenshots need no folder: their batches
                    // show under the notice (they were hidden behind it).
                    // Saved ones stay out: without access they are blank.
                    ScreenshotBatchPanel(quickLook: quickLook, onlyClipboardShots: true)
                        .padding(.top, 8)
                        .preference(key: BufferSlackKey.self, value: BufferFit.wantsAllRoom)
                }
            }
        } else if screenshots.store.isEmpty {
            VStack(spacing: 0) {
                noScreenshotsYet.padding(.top, 8)
                BufferSlackFiller()
            }
        } else {
            ScreenshotBatchPanel(quickLook: quickLook)
                .preference(key: BufferSlackKey.self, value: BufferFit.wantsAllRoom)
        }
    }

    private var noScreenshotsYet: some View {
        NoticeRow(
            symbol: "camera.viewfinder",
            title: String(localized: "No screenshots yet"),
            message: String(localized: "New screenshots (⇧⌘3, ⇧⌘4, ⇧⌘5, ⌃⇧⌘4) gather here in batches."),
            centered: true
        )
    }

    /// macOS asked once and was refused: only System Settings can allow it now.
    private func openFolderPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The latest batch above the copies (Buffer v3): a film of three frames
/// across the width, the third «+N» from four shots on (a click shows them
/// all under «Снимки»), then the action row: the handle ≡ «3 снимка» over
/// the time, «Выбрать все», «…» and the lit key. A click on a frame ticks
/// it (⇧ a range), a double click opens Quick Look, a frame drags out as its
/// file. A toast takes the handle's place.
private struct LatestBatchStrip: View {
    let batch: ScreenshotBatch
    @ObservedObject var quickLook: QuickLookService
    /// «+N»: every batch, under «Снимки».
    let onShowAll: () -> Void
    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @ObservedObject private var state = BufferTabState.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var dragToken = UUID()
    @State private var filmWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            film
            BatchActionRow(
                batch: batch,
                quickLook: quickLook,
                isLit: true,
                // A short confirmation («Скопировано · 3») only: a warning
                // says what to do next and goes to the capsule, in full.
                toast: state.toastIsWarning ? nil : state.toast.map { (message: $0, warning: false) },
                onCommand: { Self.run($0, batch: batch, quickLook: quickLook) },
                onDragBegan: dragBegan,
                onDragEnded: dragEnded
            )
            .animation(BufferTabView.fade, value: state.toast)
        }
        .onChange(of: manager.selection) {
            if quickLook.isQuickLookOpen { quickLook.updateSelection(urls: manager.pasteURLs(for: batch)) }
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: dragToken) }
    }

    private var film: some View {
        let frame = ScreenshotGridLayout.filmFrame(width: filmWidth)
        let frames = ScreenshotGridLayout.filmFrames
        let shots = Array(batch.newestFirst.prefix(frames))
        let more = ScreenshotGridLayout.filmMore(count: batch.items.count)
        return HStack(spacing: ScreenshotGridLayout.spacing) {
            ForEach(Array(shots.enumerated()), id: \.element.id) { index, item in
                let isMore = more != nil && index == frames - 1
                ScreenshotTile(
                    item: item,
                    width: frame.width,
                    isSelected: !isMore && manager.selection.contains(item.id),
                    moreCount: isMore ? more : nil,
                    onMore: isMore ? onShowAll : nil,
                    onCommand: { Self.run($0, batch: batch, quickLook: quickLook) },
                    onDragBegan: dragBegan,
                    onDragEnded: dragEnded
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: frame.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { filmWidth = $0 }
    }

    /// The film's keys, also reached from the history in «Все».
    static func run(_ command: ScreenshotGridCommand, batch: ScreenshotBatch, quickLook: QuickLookService) {
        let manager = ScreenshotShelfManager.shared
        switch command {
        case .quickLook:
            if quickLook.isQuickLookOpen {
                quickLook.hide()
            } else {
                quickLook.show(urls: manager.pasteURLs(for: batch))
            }
        case .selectAll:
            manager.selection.formUnion(batch.items.map(\.id))
        case .clearSelection:
            manager.clearSelection()
        case .removeSelected:
            manager.removeSelected(in: batch)
        case .copy:
            BufferTabState.showCopied(after: manager.copy(manager.pasteURLs(for: batch)))
        }
    }

    private func dragBegan(_ urls: [URL]) {
        manager.dragBegan(with: urls)
        vm.setAutoCloseSuppression(true, token: dragToken)
    }

    private func dragEnded(_ succeeded: Bool) {
        manager.dragEnded(succeeded: succeeded)
        vm.setAutoCloseSuppression(false, token: dragToken)
        // Dropped outside: close if the pointer is no longer over the island.
        vm.shouldRecheckHover.toggle()
    }
}
