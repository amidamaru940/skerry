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

/// "Paste into Claude · 3": copies the batch (or the screenshots selected in
/// it) and pastes it into the app the user was working in. Buffer v3: the
/// one lit key (VISUAL-E §2.3), the destination app's icon leading the
/// label, and the «куда» arrow with the recent apps (Q11). Lit only for the
/// newest batch, so a surface never shows two lit keys.
struct BatchPasteButton: View {
    let batch: ScreenshotBatch
    var isLit = true
    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @ObservedObject private var target = PasteTarget.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var showsTargets = false
    @State private var token = UUID()

    /// «Вставить в » and « · N» stay whole; a long app name gives way.
    static let labelCap: CGFloat = 215

    var body: some View {
        let count = manager.pasteURLs(for: batch).count
        let canPaste = ClipboardPaster.isAccessibilityTrusted()
        // `target` changes with the app in front, so the icon follows it.
        let icon = canPaste && target.name != nil ? ClipboardPaster.lastExternalApp?.icon : nil
        SplitPasteKey(
            icon: icon,
            isLit: isLit,
            // Without Accessibility it can only copy: no arrow (board, row 39).
            showsArrow: canPaste && !ClipboardPaster.pasteTargets.isEmpty,
            arrowIsOn: showsTargets,
            arrowHelp: String(localized: "Paste into another app"),
            action: { paste(into: nil) },
            arrowAction: { showsTargets.toggle() }
        ) {
            Text(BufferLayout.pasteTitle(count: count, target: target.name, canPaste: canPaste))
                .truncationMode(.middle)
                .frame(maxWidth: Self.labelCap)
        }
        .fixedSize()
        .help(String(localized: "Copy these screenshots and paste them into the app you were working in"))
        .popover(isPresented: $showsTargets, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                ForEach(ClipboardPaster.pasteTargets, id: \.processIdentifier) { app in
                    PasteTargetRow(app: app) {
                        showsTargets = false
                        paste(into: app)
                    }
                }
            }
            .padding(4)
            .frame(width: 240)
            .background(DSE.Palette.island)
            .presentationBackground(DSE.Palette.island)
        }
        .onChange(of: showsTargets) { _, shown in
            vm.setAutoCloseSuppression(shown, token: token)
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: token) }
    }

    private func paste(into app: NSRunningApplication?) {
        let result = manager.paste(
            batch: batch,
            target: app,
            isIslandOpen: { [vm] in vm.notchState == .open },
            // Stopped mid-way (another app came forward, the island opened):
            // the rest are on the clipboard for the user's own ⌘V.
            onStopped: { _ in BufferTabState.shared.show(toast: BufferTabState.pasteStoppedHint) }
        ) { vm.close() }
        switch result {
        case .pasted:
            break
        case .copiedOnly:
            BufferTabState.shared.show(toast: BufferTabState.copiedHint)
        case .nothingCopied:
            // The files are gone: the island stays open and says so.
            BufferTabState.shared.show(toast: String(localized: "Nothing to paste: the shots are gone"))
        }
    }
}

/// One app in the paste key's list: its icon and name.
private struct PasteTargetRow: View {
    let app: NSRunningApplication
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: DSE.Size.keyIcon, height: DSE.Size.keyIcon)
                        .accessibilityHidden(true)
                }
                Text(verbatim: app.localizedName ?? app.bundleIdentifier ?? "")
                    .eText(.body)
                    .foregroundStyle(DSE.Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: DSE.Radius.menuRow, style: .continuous)
                    .fill(isHovering ? DSE.Palette.cursor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
    }
}

/// The "…" of a batch: Quick Look, AirDrop, Finder, Markup, remove the
/// selected ones, clear the batch. Each acts on the selected screenshots of
/// the batch, or on all of them. Buffer v3: a black 280 panel, text rows,
/// the keys that do the same written on the right («Пробел», ⌫).
struct BatchActionsMenu: View {
    let batch: ScreenshotBatch
    @ObservedObject var quickLook: QuickLookService
    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var isPresented = false
    @State private var token = UUID()

    static let width: CGFloat = 280

    var body: some View {
        GlyphButton(symbol: "ellipsis", label: String(localized: "More"), isOn: isPresented) {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            let urls = manager.pasteURLs(for: batch)
            let selected = manager.selectedCount(in: batch)
            VStack(spacing: 0) {
                row("Quick Look", trailing: String(localized: "Space")) { quickLook.show(urls: urls) }
                row("AirDrop") { manager.airDrop(urls) }
                row("Show in Finder") { manager.reveal(urls) }
                if !urls.isEmpty {
                    // Several open one after another (MarkupQueue).
                    row(urls.count > 1 ? "Markup · \(urls.count)" : "Markup") { manager.markup(urls) }
                }
                Hairline()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                if selected > 0 {
                    row("Remove from batch", trailing: "⌫") { manager.removeSelected(in: batch) }
                }
                row("Clear batch") { manager.requestClear(batch) }
            }
            .padding(4)
            .frame(width: Self.width)
            .background(DSE.Palette.island)
            .presentationBackground(DSE.Palette.island)
        }
        .onChange(of: isPresented) { _, presented in
            vm.setAutoCloseSuppression(presented, token: token)
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: token) }
    }

    private func row(_ title: String.LocalizationValue, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        MoreMenuRow(title: String(localized: title), trailing: trailing, opensPanel: false) {
            isPresented = false
            action()
        }
    }
}

/// "Select All" for a batch, "Deselect" once all of it is chosen: a grey
/// word, white under the pointer, no plate.
struct BatchSelectAllButton: View {
    let batch: ScreenshotBatch
    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @State private var isHovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button {
            withAnimation(DS.hover) { manager.toggleSelectAll(in: batch) }
        } label: {
            Text(manager.isFullySelected(batch) ? String(localized: "Deselect") : String(localized: "Select All"))
                .eText(.body)
                .foregroundStyle(isHovering ? DSE.Palette.text : DSE.Palette.secondary(contrast))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: DS.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .fixedSize()
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
    }
}

/// A batch's action row (Buffer v3, the same in «Все» and «Снимки»): the
/// handle ≡ «3 снимка» over «сегодня 12:36 PM» on the left — drag it and
/// the whole batch goes — then «Выбрать все», «…» and the paste key. A
/// toast takes the handle's place while it shows.
struct BatchActionRow: View {
    let batch: ScreenshotBatch
    @ObservedObject var quickLook: QuickLookService
    var isLit = true
    var toast: (message: String, warning: Bool)? = nil
    let onCommand: (ScreenshotGridCommand) -> Void
    let onDragBegan: ([URL]) -> Void
    let onDragEnded: (Bool) -> Void

    @State private var handleHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            if let toast {
                ActionRowToast(
                    symbol: toast.warning ? "exclamationmark.circle" : "checkmark",
                    tint: toast.warning ? DS.Palette.attention : DSE.Palette.text,
                    message: toast.message
                )
                .help(toast.message)
                .transition(.opacity)
            } else {
                handle
                    .transition(.opacity)
                Spacer(minLength: 12)
            }
            BatchSelectAllButton(batch: batch)
            BatchActionsMenu(batch: batch, quickLook: quickLook)
            BatchPasteButton(batch: batch, isLit: isLit)
                .padding(.leading, 6)
        }
        .frame(height: DSE.Size.key)
    }

    /// The title is the handle for dragging the whole batch out.
    private var handle: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(handleHovered ? DSE.Palette.text : DSE.Palette.tertiary(contrast))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(ScreenshotBatchTitle.count(for: batch))
                    .eText(.title)
                    .foregroundStyle(DSE.Palette.text)
                Text(ScreenshotBatchTitle.when(for: batch, lowercased: true))
                    .eText(.caption)
                    .foregroundStyle(DSE.Palette.tertiary(contrast))
            }
            .lineLimit(1)
        }
        .fixedSize()
        .contentShape(Rectangle())
        .overlay(
            ScreenshotDragSource(
                image: nil,
                onClick: { _ in },
                urlsForDrag: { batch.items.map(\.url) },
                onDragBegan: onDragBegan,
                onDragEnded: onDragEnded,
                onCommand: onCommand
            )
        )
        .onHover { hovering in withAnimation(DS.hover) { handleHovered = hovering } }
        .help(String(localized: "Drag to take the whole batch"))
        .accessibilityElement(children: .combine)
    }
}
