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

/// The Clipboard tab: filters and search, pinned items on top, then recent
/// copies. Click copies an item back, double-click or Return pastes it into
/// the app in front (Shift: as plain text), ⌘1…⌘9 paste the numbered items,
/// cards drag out to other apps. Also used, with two fixed columns, as the
/// clipboard half of the Notes tab in "separate tab" mode.
struct NotchClipboardView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.clipboardHistoryPaused) private var paused
    @ObservedObject private var presentation = ScreenPresentation.shared
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

    /// Inside the merged Clipboard tab (`BufferTabView`), which owns the
    /// segments, search, pause and "…"; this view shows only the history.
    var embedded = false
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

    /// Pinned entries fold into one row in the merged tab until opened
    /// (always open while searching).
    private var showsPinnedCards: Bool {
        !embedded || bufferState.showsPinned || !activeQuery.isEmpty
    }

    /// Order of the ⌘1…⌘9 numbers: the pinned on screen first, then recent.
    private var numbered: [ClipboardItem] { (showsPinnedCards ? pinned : []) + recent }

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
            if clipboardManager.clipboardHistory.isEmpty && clipboardManager.pinnedItems.isEmpty {
                if !paused { emptyState }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !pinned.isEmpty {
                            if embedded {
                                pinnedFoldRow
                            } else {
                                sectionTitle("Pinned", systemImage: "pin.fill")
                            }
                            if showsPinnedCards {
                                grid(pinned, numberOffset: 0)
                            }
                        }
                        if !recent.isEmpty {
                            if !pinned.isEmpty && showsPinnedCards { sectionTitle("Recent", systemImage: "clock") }
                            grid(recent, numberOffset: showsPinnedCards ? pinned.count : 0)
                        }
                        if pinned.isEmpty && recent.isEmpty {
                            Text("Nothing matches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                        }
                    }
                    .padding(.horizontal, embedded ? 0 : 20)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Return / ⌘1…⌘9 also work after a click on empty space in the tab,
        // and right away when the island was opened with a shortcut.
        .background(IslandKeyCatcher(onKey: handleKey))
        .onHover { updateSuppression(for: $0) }
        .onDisappear {
            updateSuppression(for: false)
            vm.setAutoCloseSuppression(false, token: autoCloseToken)
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
        .onAppear {
            if Defaults[.enableClipboardManager], !clipboardManager.isMonitoring {
                clipboardManager.startMonitoring()
            }
        }
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

    private var emptyState: some View {
        DSEmptyState(
            symbol: "doc.on.clipboard",
            title: String(localized: "No copies yet"),
            message: String(localized: "Copy something to see it here")
        )
        .padding(.vertical, 12)
    }

    /// One calm line instead of an empty screen that said "paused" and
    /// "copy something" at once.
    private var pausedBanner: some View {
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
        .padding(.horizontal, embedded ? 0 : 20)
        .padding(.bottom, 8)
    }

    /// "Pinned · 3" in one row; a click opens or folds the pinned cards.
    private var pinnedFoldRow: some View {
        Button {
            withAnimation(DS.spring) { bufferState.showsPinned.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Pinned")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(pinned.count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(DS.Palette.textTertiary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(showsPinnedCards ? 90 : 0))
            }
            .foregroundStyle(DS.Palette.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(showsPinnedCards ? "Hide pinned" : "Show pinned"))
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
                .overlay(
                    ClipboardCardInteraction(
                        writers: { ClipboardDragWriters.writers(for: item) },
                        dragImage: { item.type == .image ? item.getImageData().flatMap(NSImage.init(data:)) : nil },
                        onClick: { copy(item) },
                        onDoubleClick: { shift in paste(item, plainText: shift) },
                        onDragChanged: { dragging in
                            if dragging { clipboardManager.markDragStart() } else { clipboardManager.isDraggingItem = false }
                        },
                        onKey: handleKey
                    )
                )
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
        guard let action = ClipboardKeyAction(event: event) else { return false }
        switch action {
        case .pasteSelected(let plain):
            guard let item = numbered.first(where: { $0.id == selectedId }) ?? numbered.first else { return false }
            paste(item, plainText: plain)
        case .pasteNumber(let index, let plain):
            guard numbered.indices.contains(index) else { return false }
            paste(numbered[index], plainText: plain)
        }
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

/// Icon of the app a copy came from.
private struct SourceAppIcon: View {
    let bundleID: String?

    var body: some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 14, height: 14)
                .help(FileManager.default.displayName(atPath: url.path))
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
        }
    }
}

// MARK: - AppKit input

/// Clicks, double-clicks, drags and keys for a clipboard card.
private struct ClipboardCardInteraction: NSViewRepresentable {
    let writers: () -> [NSPasteboardWriting]
    let dragImage: () -> NSImage?
    let onClick: () -> Void
    let onDoubleClick: (_ shift: Bool) -> Void
    let onDragChanged: (Bool) -> Void
    let onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ClipboardCardInteractionView { update(ClipboardCardInteractionView()) }
    func updateNSView(_ view: ClipboardCardInteractionView, context: Context) { _ = update(view) }

    private func update(_ view: ClipboardCardInteractionView) -> ClipboardCardInteractionView {
        view.writers = writers
        view.dragImage = dragImage
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
