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

/// The screenshot batches in the Clipboard tab («Снимки»): per batch the
/// action row (as in «Все») and its frames in rows, newest batch first. A
/// click adds or removes a screenshot, Cmd+A selects all, Esc deselects,
/// space opens Quick Look, Cmd+C copies, dragging carries every selected
/// file. Buffer v3: the newest batch's key is lit, the others' are not
/// (one light per state).
struct ScreenshotBatchPanel: View {
    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @ObservedObject var quickLook: QuickLookService
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Default(.screenshotThumbnailSize) private var thumbnailWidth
    @State private var dragToken = UUID()
    @State private var gridWidth: CGFloat = 0
    /// Without access to the screenshot folder: only the temporary clipboard
    /// shots, the ones Skerry can show; the saved ones would be blank frames.
    var onlyClipboardShots = false

    /// The batches shown: all, or only their temporary clipboard shots
    /// (by the path's text alone, so the guarded folder is never touched).
    static func visibleBatches(_ batches: [ScreenshotBatch], onlyClipboardShots: Bool) -> [ScreenshotBatch] {
        guard onlyClipboardShots else { return batches }
        return batches.compactMap { batch in
            var kept = batch
            kept.items = batch.items.filter { TemporaryClipboardShots.holds(path: $0.path) }
            return kept.items.isEmpty ? nil : kept
        }
    }

    private var batches: [ScreenshotBatch] {
        Self.visibleBatches(manager.store.batches, onlyClipboardShots: onlyClipboardShots)
    }

    var body: some View {
        let batches = batches
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(batches) { batch in
                        batchSection(batch, isNewest: batch.id == batches.first?.id)
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

    private func batchSection(_ batch: ScreenshotBatch, isNewest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BatchActionRow(
                batch: batch,
                quickLook: quickLook,
                isLit: isNewest,
                onCommand: run,
                onDragBegan: dragBegan,
                onDragEnded: dragEnded
            )
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
            if onlyClipboardShots {
                manager.selection = Set(batches.flatMap(\.items).map(\.id))
            } else {
                manager.selectAll()
            }
        case .clearSelection:
            manager.clearSelection()
        case .removeSelected:
            manager.requestRemoval(manager.selection)
        case .copy:
            BufferTabState.showCopied(after: manager.copySelected())
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
        // Dropped outside: close if the pointer is no longer over the island.
        vm.shouldRecheckHover.toggle()
    }
}

/// "Today 20:31 · 3 screenshots", "Yesterday 18:02 · 1 screenshot",
/// "14 Oct 09:15 · 5 screenshots" — with the language's plural forms. The
/// action row splits it: «3 снимка» over «сегодня 12:36 PM».
enum ScreenshotBatchTitle {
    static func make(for batch: ScreenshotBatch, now: Date = Date(), calendar: Calendar = .current,
                     bundle: Bundle = .main, locale: Locale = .current) -> String {
        let countFormat = bundle.localizedString(forKey: "%lld screenshots", value: "%lld screenshots", table: nil)
        let count = String(format: countFormat, locale: locale, batch.items.count)
        return "\(when(for: batch, now: now, calendar: calendar, bundle: bundle, locale: locale)) · \(count)"
    }

    /// «3 снимка»: the action row's title.
    static func count(for batch: ScreenshotBatch, bundle: Bundle = .main, locale: Locale = .current) -> String {
        let countFormat = bundle.localizedString(forKey: "%lld shots", value: "%lld shots", table: nil)
        return String(format: countFormat, locale: locale, batch.items.count)
    }

    /// "Today 20:31"; `lowercased` gives «сегодня 12:36 PM», the caption
    /// under the count.
    static func when(for batch: ScreenshotBatch, now: Date = Date(), calendar: Calendar = .current,
                     bundle: Bundle = .main, locale: Locale = .current, lowercased: Bool = false) -> String {
        let start = batch.startedAt
        let time = start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        var day: String
        if calendar.isDate(start, inSameDayAs: now) {
            day = bundle.localizedString(forKey: "Today", value: "Today", table: nil)
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(start, inSameDayAs: yesterday) {
            day = bundle.localizedString(forKey: "Yesterday", value: "Yesterday", table: nil)
        } else {
            day = start.formatted(Date.FormatStyle().day().month(.abbreviated).locale(locale))
        }
        if lowercased { day = day.lowercased(with: locale) }
        return "\(day) \(time)"
    }
}

/// One film frame with the AppKit click/drag layer on top (VISUAL-E §2.7):
/// 16:10, radius 8, a 0.5 pt rim (0.25 under the pointer), the accent rim
/// with its glow when ticked, no badge. With `moreCount` it is the last frame
/// of a long film: the shot at 0.35 under «+N», and a click shows them all.
struct ScreenshotTile: View {
    let item: ScreenshotItem
    let width: Double
    let isSelected: Bool
    var moreCount: Int? = nil
    var onMore: (() -> Void)? = nil
    let onCommand: (ScreenshotGridCommand) -> Void
    let onDragBegan: ([URL]) -> Void
    let onDragEnded: (Bool) -> Void

    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @State private var image: NSImage?
    @State private var isHovering = false

    var size: CGSize { CGSize(width: width, height: (width * ScreenshotGridLayout.aspect).rounded()) }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                DSE.Palette.placeholder
                Image(systemName: item.url.pathExtension.lowercased() == "mov" ? "video" : "photo")
                    .font(.system(size: 15))
                    .foregroundStyle(DSE.Palette.textTertiary)
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(moreCount == nil ? 1 : DSE.Opacity.disabled)
        .overlay {
            if let moreCount {
                Text(verbatim: "+\(moreCount)")
                    .eText(.plusN)
                    .foregroundStyle(DSE.Palette.text)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DSE.Radius.frame, style: .continuous))
        .hairlineRim(cornerRadius: DSE.Radius.frame, emphasized: isHovering)
        .selectionRim(isSelected)
        .overlay { interaction }
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
        .help(moreCount == nil ? item.url.lastPathComponent : BufferSegment.screenshots.title)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: moreCount.map { "+\($0), \(BufferSegment.screenshots.title)" } ?? item.url.lastPathComponent))
        .accessibilityAddTraits(moreCount != nil ? .isButton : (isSelected ? .isSelected : []))
        .accessibilityAction { onMore?() }
        .task(id: "\(item.path)|\(Int(width / 40))") {
            // Re-render only when the size moves to a new step, not on every slider tick.
            let step = (width / 40).rounded(.up) * 40
            image = await ScreenshotThumbnails.shared.thumbnail(for: item.url, size: CGSize(width: step * 2, height: step * 1.3))
        }
    }

    @ViewBuilder
    private var interaction: some View {
        if let onMore {
            Button(action: onMore) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(PressDimStyle())
        } else {
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
    static let spacing: CGFloat = DSE.Size.filmGap
    /// Frames are 16:10, the shape of a Mac screenshot (184 × 115).
    static let aspect: CGFloat = DSE.Size.film.height / DSE.Size.film.width

    /// The latest batch's film: three frames across the width, `spacing`
    /// apart (184 × 115 across the 570 content). Before the width is known,
    /// the E size.
    static func filmFrame(width: CGFloat) -> CGSize {
        guard width > 0 else { return DSE.Size.film }
        let tile = ((width - spacing * 2) / 3).rounded(.down)
        return CGSize(width: tile, height: (tile * aspect).rounded())
    }

    /// The film's frames in «Все»: up to three; from four shots on, the third
    /// is «+N», N the shots not shown.
    static let filmFrames = 3

    static func filmMore(count: Int) -> Int? {
        count > filmFrames ? count - (filmFrames - 1) : nil
    }

    /// The thumbnail sizes of the «Снимки» line, small to large: 4, 3 and 2
    /// frames a row across the 570 content (the setting keeps its 70…200).
    static let sizeSteps: [Double] = [110, 160, 200]

    /// The step nearest a stored size.
    static func sizeStep(for width: Double) -> Int {
        sizeSteps.indices.min { abs(sizeSteps[$0] - width) < abs(sizeSteps[$1] - width) } ?? 0
    }

    static func columns(width: CGFloat, minimumTile: CGFloat) -> (count: Int, tile: CGFloat) {
        guard width > 0, minimumTile > 0 else { return (1, minimumTile) }
        let count = max(1, Int((width + spacing) / (minimumTile + spacing)))
        let tile = ((width - spacing * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
        return (count, tile)
    }
}
