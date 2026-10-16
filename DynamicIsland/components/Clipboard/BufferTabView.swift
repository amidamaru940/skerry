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
/// §3.4): the latest screenshot batch on top with "Paste into … · N", then
/// the copies, with the segments All · Screenshots · Text · Links · Files.
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
    @State private var searching = false
    @State private var showClearAlert = false
    @State private var menuShown = false
    @State private var alertToken = UUID()
    @State private var trashToken = UUID()

    private var available: [BufferSegment] {
        BufferSegment.available(clipboard: clipboardOn && clipboardMode == .notchTab, screenshots: screenshotsOn)
    }

    private var segment: BufferSegment? {
        BufferSegment.resolve(state.segment, available: available)
    }

    var body: some View {
        if presentation.isHidingContent {
            PresentingPlaceholder(title: NotchTab.clipboard.title, icon: NotchTab.clipboard.icon)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let batch = screenshots.store.batches.first, let segment,
                   BufferLayout.showsBatchStrip(segment: segment, lastAddedAt: batch.lastAddedAt, now: Date()) {
                    LatestBatchStrip(batch: batch, quickLook: quickLook)
                }
                if available.count > 1 {
                    segmentsRow
                }
                content
            }
            .onPreferenceChange(BufferSlackKey.self) { slack in
                MainActor.assumeIsolated { state.fit(slack: slack) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) {
                if let toast = state.toast {
                    DSToastView(text: toast, tone: state.toastIsWarning ? .warning : .done)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(DS.spring, value: state.toast)
            .quickLookPresenter(using: quickLook)
            .alert("Clear Clipboard History?", isPresented: $showClearAlert) {
                Button("Clear History", role: .destructive) { clipboard.clearHistory() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every recent clipboard item. Pinned items stay.")
            }
            .onChange(of: showClearAlert) { _, shown in
                vm.setAutoCloseSuppression(shown, token: alertToken)
            }
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
        }
    }

    // MARK: Segments, search, pause, "…"

    private var segmentsRow: some View {
        HStack(spacing: 8) {
            if searching {
                searchField
            } else {
                DSSegmented(
                    options: available.map { (value: $0, title: $0.title) },
                    selection: Binding(get: { segment ?? .all }, set: { state.segment = $0 })
                )
                .fixedSize()
            }
            Spacer(minLength: 4)
            if segment == .screenshots {
                Slider(value: $thumbnailWidth, in: 70...200)
                    .controlSize(.mini)
                    .frame(width: 80)
                    .help(String(localized: "Thumbnail size"))
                    .accessibilityLabel(Text("Thumbnail size"))
            } else if clipboardOn {
                DSIconButton(symbol: "magnifyingglass", label: String(localized: "Search"), isSelected: searching) {
                    withAnimation(DS.spring) {
                        searching.toggle()
                        if !searching { state.query = "" }
                    }
                }
                DSIconButton(
                    symbol: paused ? "play.fill" : "pause.fill",
                    label: paused ? String(localized: "Resume clipboard history") : String(localized: "Pause clipboard history"),
                    tint: paused ? DS.Palette.paused : nil
                ) {
                    paused.toggle()
                }
                DSIconButton(symbol: "ellipsis", label: String(localized: "More"), isSelected: menuShown) {
                    menuShown.toggle()
                }
                .popover(isPresented: $menuShown, arrowEdge: .bottom) {
                    VStack(spacing: 2) {
                        MoreMenuRow(symbol: "trash", title: String(localized: "Clear History…"), trailing: nil,
                                    trailingTint: DS.Palette.textTertiary, opensPanel: false) {
                            menuShown = false
                            showClearAlert = true
                        }
                        MoreMenuRow(symbol: "gearshape", title: String(localized: "Clipboard Settings…"), trailing: nil,
                                    trailingTint: DS.Palette.textTertiary, opensPanel: false) {
                            menuShown = false
                            SettingsWindowController.shared.showWindow()
                        }
                    }
                    .padding(6)
                    .frame(width: 240)
                }
                .onChange(of: menuShown) { _, shown in
                    vm.setAutoCloseSuppression(shown, token: alertToken)
                }
            }
        }
        .frame(height: 30)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textTertiary)
            TextField(String(localized: "Search"), text: $state.query)
                .textFieldStyle(.plain)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.text)
            if !state.query.isEmpty {
                Button { state.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(maxWidth: 260)
        .background(Capsule().fill(DS.Palette.card))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .screenshots:
            screenshotsContent
        case .none:
            VStack(spacing: 0) {
                DSEmptyState(
                    symbol: "doc.on.clipboard",
                    title: String(localized: "Clipboard is off"),
                    message: String(localized: "Turn on the clipboard or screenshot collecting in Settings."),
                    inline: true
                )
                BufferSlackFiller()
            }
        default:
            NotchClipboardView(embedded: true)
        }
    }

    @ViewBuilder
    private var screenshotsContent: some View {
        if !screenshots.canReadFolder {
            VStack(spacing: 0) {
                DSEmptyState(
                    symbol: "lock",
                    title: String(localized: "No access to the screenshot folder"),
                    message: String(localized: "macOS keeps Skerry out of this folder. Choose ~/Screenshots in Screenshots settings, or allow access in System Settings."),
                    inline: true
                )
                BufferSlackFiller()
            }
        } else if screenshots.store.isEmpty {
            VStack(spacing: 0) {
                DSEmptyState(
                    symbol: "camera.viewfinder",
                    title: String(localized: "No screenshots yet"),
                    message: String(localized: "New screenshots (⇧⌘3, ⇧⌘4, ⇧⌘5) gather here in batches."),
                    inline: true
                )
                BufferSlackFiller()
            }
        } else {
            ScreenshotBatchPanel(quickLook: quickLook)
                .preference(key: BufferSlackKey.self, value: BufferFit.wantsAllRoom)
        }
    }
}

/// The latest batch above the copies: its title (drag it to take the whole
/// batch), "…" and "Paste into … · N", then its screenshots in one row.
/// Click a screenshot to paste only it (⌘-click for several).
private struct LatestBatchStrip: View {
    let batch: ScreenshotBatch
    @ObservedObject var quickLook: QuickLookService
    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var dragToken = UUID()
    @State private var headerHovered = false

    static let thumbnailWidth: Double = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                header
                Spacer(minLength: 4)
                BatchSelectAllButton(batch: batch)
                BatchActionsMenu(batch: batch, quickLook: quickLook)
                BatchPasteButton(batch: batch)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(batch.newestFirst) { item in
                        ScreenshotTile(
                            item: item,
                            width: Self.thumbnailWidth,
                            isSelected: manager.selection.contains(item.id),
                            onCommand: run,
                            onDragBegan: dragBegan,
                            onDragEnded: dragEnded
                        )
                    }
                }
            }
            .frame(height: (Self.thumbnailWidth * 0.62).rounded())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous).fill(DS.Palette.surface))
        .onDisappear { vm.setAutoCloseSuppression(false, token: dragToken) }
    }

    /// The title is the handle for dragging the whole batch out.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(headerHovered ? DS.Palette.textSecondary : DS.Palette.textTertiary)
            Text(ScreenshotBatchTitle.make(for: batch))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.text)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(headerHovered ? DS.Palette.hoverFill : .clear)
        )
        .overlay(
            ScreenshotDragSource(
                image: nil,
                onClick: { _ in },
                urlsForDrag: { batch.items.map(\.url) },
                onDragBegan: dragBegan,
                onDragEnded: dragEnded,
                onCommand: run
            )
        )
        .onHover { hovering in withAnimation(DS.hover) { headerHovered = hovering } }
        .help(String(localized: "Drag to take the whole batch"))
    }

    private func run(_ command: ScreenshotGridCommand) {
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
            let urls = manager.pasteURLs(for: batch)
            manager.copy(urls)
            BufferTabState.shared.show(toast: BufferTabState.copiedScreenshots(urls.count), warning: false, for: 2)
        }
    }

    private func dragBegan(_ urls: [URL]) {
        manager.dragBegan(with: urls)
        vm.setAutoCloseSuppression(true, token: dragToken)
    }

    private func dragEnded(_ succeeded: Bool) {
        manager.dragEnded(succeeded: succeeded)
        vm.setAutoCloseSuppression(false, token: dragToken)
    }
}
