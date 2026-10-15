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
import QuickLookThumbnailing
import SwiftUI

/// The screenshot batches in the Clipboard tab: a grid of thumbnails per
/// batch, newest first, each with Select All, "…" and "Paste". A click
/// adds or removes a screenshot, Cmd+A selects all, Esc deselects, space
/// opens Quick Look, Cmd+C copies, dragging carries every selected file.
/// (Its own title and button row, for the old Screenshots tab, went with
/// that tab.)
struct ScreenshotBatchPanel: View {
    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @ObservedObject var quickLook: QuickLookService
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Default(.screenshotThumbnailSize) private var thumbnailWidth
    @State private var dragToken = UUID()
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(manager.store.batches) { batch in
                        batchSection(batch)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                .padding(.bottom, 6)
            }
        }
        // Space, Delete, ⌘A, ⌘C also work right after opening the tab with a
        // shortcut, before any tile was clicked.
        .background(IslandKeyCatcher { event in
            guard let command = ScreenshotGridCommand(event: event) else { return false }
            run(command)
            return true
        })
        .onChange(of: manager.selection) {
            if quickLook.isQuickLookOpen { quickLook.updateSelection(urls: manager.selectedURLs) }
        }
        .onDisappear {
            vm.setAutoCloseSuppression(false, token: dragToken)
        }
    }

    // MARK: Grid

    private func batchSection(_ batch: ScreenshotBatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(ScreenshotBatchTitle.make(for: batch))
                    // As the latest-batch strip and "Pinned" above it.
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                BatchSelectAllButton(batch: batch)
                BatchActionsMenu(batch: batch, quickLook: quickLook)
                BatchPasteButton(batch: batch, kind: .secondary)
            }
            let grid = ScreenshotGridLayout.columns(width: gridWidth, minimumTile: thumbnailWidth)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(grid.tile), spacing: ScreenshotGridLayout.spacing), count: grid.count),
                alignment: .leading,
                spacing: ScreenshotGridLayout.spacing
            ) {
                ForEach(batch.newestFirst) { item in
                    ScreenshotTile(
                        item: item,
                        width: grid.tile,
                        isSelected: manager.selection.contains(item.id),
                        onCommand: run,
                        onDragBegan: dragBegan,
                        onDragEnded: dragEnded
                    )
                }
            }
        }
    }

    // MARK: Commands

    private func run(_ command: ScreenshotGridCommand) {
        switch command {
        case .quickLook:
            if quickLook.isQuickLookOpen {
                quickLook.hide()
            } else if !manager.selectedURLs.isEmpty {
                quickLook.show(urls: manager.selectedURLs)
            }
        case .selectAll:
            manager.selectAll()
        case .clearSelection:
            manager.clearSelection()
        case .removeSelected:
            manager.requestRemoval(manager.selection)
        case .copy:
            manager.copySelected()
            if !manager.selectedURLs.isEmpty {
                BufferTabState.shared.show(toast: BufferTabState.copiedScreenshots(manager.selectedURLs.count), warning: false, for: 2)
            }
        }
    }

    private func dragBegan(_ urls: [URL]) {
        manager.dragBegan(with: urls)
        // Keep the island open while the files are being dragged out.
        vm.setAutoCloseSuppression(true, token: dragToken)
    }

    private func dragEnded(_ succeeded: Bool) {
        manager.dragEnded(succeeded: succeeded)
        vm.setAutoCloseSuppression(false, token: dragToken)
    }
}

/// "Today 20:31 · 3 screenshots", "Yesterday 18:02 · 1 screenshot",
/// "14 Oct 09:15 · 5 screenshots" — with the language's plural forms.
enum ScreenshotBatchTitle {
    static func make(for batch: ScreenshotBatch, now: Date = Date(), calendar: Calendar = .current,
                     bundle: Bundle = .main, locale: Locale = .current) -> String {
        let start = batch.startedAt
        let time = start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        let day: String
        if calendar.isDate(start, inSameDayAs: now) {
            day = bundle.localizedString(forKey: "Today", value: "Today", table: nil)
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(start, inSameDayAs: yesterday) {
            day = bundle.localizedString(forKey: "Yesterday", value: "Yesterday", table: nil)
        } else {
            day = start.formatted(Date.FormatStyle().day().month(.abbreviated).locale(locale))
        }
        let countFormat = bundle.localizedString(forKey: "%lld screenshots", value: "%lld screenshots", table: nil)
        let count = String(format: countFormat, locale: locale, batch.items.count)
        return "\(day) \(time) · \(count)"
    }
}

/// One thumbnail with the AppKit click/drag layer on top.
struct ScreenshotTile: View {
    let item: ScreenshotItem
    let width: Double
    let isSelected: Bool
    let onCommand: (ScreenshotGridCommand) -> Void
    let onDragBegan: ([URL]) -> Void
    let onDragEnded: (Bool) -> Void

    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @State private var image: NSImage?

    var size: CGSize { CGSize(width: width, height: (width * 0.62).rounded()) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.06))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.url.pathExtension.lowercased() == "mov" ? "video" : "photo")
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 2.5 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(3)
            }
        }
        .overlay(
            ScreenshotDragSource(
                image: image,
                onClick: { click in
                    manager.click(item, extend: click.extend, range: click.range, double: click.double)
                    if click.double { onCommand(.quickLook) }
                },
                urlsForDrag: { manager.dragURLs(startingAt: item) },
                onDragBegan: onDragBegan,
                onDragEnded: onDragEnded,
                onCommand: onCommand
            )
        )
        .help(item.url.lastPathComponent)
        .accessibilityElement()
        .accessibilityLabel(Text(item.url.lastPathComponent))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: "\(item.path)|\(Int(width / 40))") {
            // Re-render only when the size moves to a new step, not on every slider tick.
            let step = (width / 40).rounded(.up) * 40
            image = await ScreenshotThumbnails.shared.thumbnail(for: item.url, size: CGSize(width: step * 2, height: step * 1.3))
        }
    }
}

/// Plain (undecorated) thumbnails, cached by path and size.
actor ScreenshotThumbnails {
    static let shared = ScreenshotThumbnails()
    private var cache: [String: NSImage] = [:]

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[key] { return cached }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache[key] = image
        if cache.count > 300 { cache.removeAll() }
        return image
    }
}

/// Closed-island flash for a new screenshot: [thumbnail] ─── [ notch ] ─── [count].
struct ScreenshotFlashLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let flash: ScreenshotShelfManager.Flash
    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 30, height: max(vm.effectiveClosedNotchHeight - 10, 14))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .frame(width: 34, alignment: .leading)

            Rectangle()
                .fill(Color.black)
                .frame(width: vm.closedNotchSize.width)

            Text("\(flash.count)")
                .font(.system(.callout, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: false))
                .frame(width: 34, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .task(id: flash.id) {
            image = await ScreenshotThumbnails.shared.thumbnail(for: flash.url, size: CGSize(width: 60, height: 40))
        }
        .accessibilityLabel(Text("New screenshot, \(flash.count) in batch"))
    }
}

/// The screenshot grid fills its width: as many columns as tiles of at
/// least the chosen size fit, stretched to share what is left. Fixed-size
/// tiles left up to a tile's width empty on the right.
enum ScreenshotGridLayout {
    static let spacing: CGFloat = 8

    static func columns(width: CGFloat, minimumTile: CGFloat) -> (count: Int, tile: CGFloat) {
        guard width > 0, minimumTile > 0 else { return (1, minimumTile) }
        let count = max(1, Int((width + spacing) / (minimumTile + spacing)))
        let tile = ((width - spacing * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
        return (count, tile)
    }
}
