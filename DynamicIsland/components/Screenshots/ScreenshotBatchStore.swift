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

/// A screenshot in a batch. Only the path and the capture time are kept;
/// the file itself stays where macOS saved it.
struct ScreenshotItem: Codable, Hashable, Identifiable {
    let path: String
    let capturedAt: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

/// Screenshots taken in a row. Items are kept in capture order.
struct ScreenshotBatch: Codable, Equatable, Identifiable {
    let id: UUID
    var items: [ScreenshotItem]
    var lastAddedAt: Date

    var startedAt: Date { items.first?.capturedAt ?? lastAddedAt }
    /// Display order: newest first.
    var newestFirst: [ScreenshotItem] { items.reversed() }
}

/// Groups screenshots into batches and persists the list of paths.
///
/// A screenshot joins the newest batch unless more than `batchGap` has passed
/// since that batch's last screenshot, or the batch was cleared; then a new
/// batch starts. Batches are kept newest first.
final class ScreenshotBatchStore: ObservableObject {
    @Published private(set) var batches: [ScreenshotBatch] = []
    /// The newest batch was cleared: the next screenshot starts a new one.
    private var startFreshBatch = false

    private let fileURL: URL?
    private let batchGap: () -> TimeInterval
    private let fileExists: (String) -> Bool

    /// - Parameters:
    ///   - fileURL: where the batches are saved; nil keeps them in memory.
    ///   - batchGap: the longest pause between screenshots of one batch.
    ///   - pruneOnLoad: drop screenshots whose files are gone right away.
    ///     The app's own store leaves it to ScreenshotShelfManager.start():
    ///     the files are usually on the Desktop, and looking at them before
    ///     macOS has answered the folder question blocked launch.
    init(
        fileURL: URL?,
        batchGap: @escaping () -> TimeInterval,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        pruneOnLoad: Bool = true
    ) {
        self.fileURL = fileURL
        self.batchGap = batchGap
        self.fileExists = fileExists
        load()
        if pruneOnLoad { pruneMissingFiles() }
    }

    var currentBatch: ScreenshotBatch? { batches.first }
    var allItems: [ScreenshotItem] { batches.flatMap(\.items) }
    var isEmpty: Bool { batches.isEmpty }

    func contains(path: String) -> Bool {
        batches.contains { batch in batch.items.contains { $0.path == path } }
    }

    /// Adds a screenshot; returns false for a path that is already in a batch.
    @discardableResult
    func add(_ url: URL, capturedAt date: Date) -> Bool {
        let path = url.standardizedFileURL.path
        guard !contains(path: path) else { return false }
        let item = ScreenshotItem(path: path, capturedAt: date)

        let startsFresh = startFreshBatch
        startFreshBatch = false
        if !startsFresh, var current = batches.first, date.timeIntervalSince(current.lastAddedAt) <= batchGap() {
            current.items.append(item)
            current.lastAddedAt = max(current.lastAddedAt, date)
            batches[0] = current
        } else {
            batches.insert(ScreenshotBatch(id: UUID(), items: [item], lastAddedAt: date), at: 0)
        }
        save()
        return true
    }

    /// Removes the given screenshots from their batches (the files stay).
    @discardableResult
    func remove(_ ids: Set<String>) -> [ScreenshotItem] {
        var removed: [ScreenshotItem] = []
        for index in batches.indices {
            removed += batches[index].items.filter { ids.contains($0.id) }
            batches[index].items.removeAll { ids.contains($0.id) }
        }
        dropEmptyBatches()
        save()
        return removed
    }

    /// What `takeOut` removed, for «Отменить»: each batch it touched, holding
    /// only the screenshots taken from it, with the place it had.
    struct Removal: Equatable {
        struct Entry: Equatable {
            let index: Int
            let batch: ScreenshotBatch
        }

        fileprivate(set) var entries: [Entry] = []
        /// Whether the next screenshot was to start a new batch before.
        fileprivate var startedFresh = false

        init() {}

        var items: [ScreenshotItem] { entries.flatMap(\.batch.items) }
        var count: Int { items.count }
        var isEmpty: Bool { entries.isEmpty }
    }

    /// Takes the given screenshots out of their batches, keeping what
    /// `restore` needs to put them back (the files stay).
    func takeOut(_ ids: Set<String>) -> Removal {
        var removal = Removal()
        for (index, batch) in batches.enumerated() {
            let taken = batch.items.filter { ids.contains($0.id) }
            guard !taken.isEmpty else { continue }
            var part = batch
            part.items = taken
            removal.entries.append(.init(index: index, batch: part))
        }
        guard !removal.isEmpty else { return removal }
        removal.startedFresh = startFreshBatch
        // The newest batch emptied: the next screenshot starts a new one, as
        // after `clear`.
        if let newest = batches.first, newest.items.allSatisfy({ ids.contains($0.id) }) {
            startFreshBatch = true
        }
        for index in batches.indices {
            batches[index].items.removeAll { ids.contains($0.id) }
        }
        dropEmptyBatches()
        save()
        return removal
    }

    /// Puts what `takeOut` removed back: into its batch when that is still
    /// there, otherwise as a batch in its place by time (newest first), so a
    /// screenshot taken meanwhile stays on top. A screenshot that is in a
    /// batch again meanwhile is not doubled.
    func restore(_ removal: Removal) {
        let newestBefore = batches.first?.id
        for entry in removal.entries {
            let missing = entry.batch.items.filter { !contains(path: $0.path) }
            guard !missing.isEmpty else { continue }
            if let index = batches.firstIndex(where: { $0.id == entry.batch.id }) {
                batches[index].items = (batches[index].items + missing).sorted { $0.capturedAt < $1.capturedAt }
            } else {
                var batch = entry.batch
                batch.items = missing
                let place = batches.firstIndex { $0.lastAddedAt < batch.lastAddedAt } ?? batches.count
                batches.insert(batch, at: place)
            }
        }
        // Back on top: the next screenshot joins it as before the clear.
        if let newest = batches.first?.id, newest != newestBefore,
           removal.entries.contains(where: { $0.batch.id == newest }) {
            startFreshBatch = removal.startedFresh
        }
        save()
    }

    /// In every batch that has a selected screenshot, removes the others.
    /// Batches without a selected screenshot are left alone.
    @discardableResult
    func keepOnly(_ ids: Set<String>) -> [ScreenshotItem] {
        var removed: [ScreenshotItem] = []
        for index in batches.indices where batches[index].items.contains(where: { ids.contains($0.id) }) {
            removed += batches[index].items.filter { !ids.contains($0.id) }
            batches[index].items.removeAll { !ids.contains($0.id) }
        }
        dropEmptyBatches()
        save()
        return removed
    }

    /// Empties a batch. When it was the newest one, the next screenshot
    /// starts a new batch.
    @discardableResult
    func clear(batchID: UUID) -> [ScreenshotItem] {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return [] }
        let removed = batches[index].items
        batches.remove(at: index)
        // Otherwise the next screenshot joined the older batch below it.
        if index == 0 { startFreshBatch = true }
        save()
        return removed
    }

    /// Drops screenshots whose files no longer exist. `only` limits the look
    /// to some paths (the temporary clipboard ones, before the screenshot
    /// folder may be looked at); the others are not checked at all.
    func pruneMissingFiles(only include: (String) -> Bool = { _ in true }) {
        // Checked on a copy: changing the published batches in place, even
        // removing nothing, re-drew every view that shows them.
        var pruned = batches
        var changed = false
        for index in pruned.indices {
            let before = pruned[index].items.count
            pruned[index].items.removeAll { include($0.path) && !fileExists($0.path) }
            changed = changed || pruned[index].items.count != before
        }
        let countBefore = pruned.count
        pruned.removeAll { $0.items.isEmpty }
        guard changed || pruned.count != countBefore else { return }
        batches = pruned
        save()
    }

    /// File URLs for dragging, copying or sharing the given screenshots, in
    /// the order they were taken (oldest first, older batches first).
    func fileURLs(for ids: Set<String>) -> [URL] {
        batches.reversed().flatMap(\.items).filter { ids.contains($0.id) }.map(\.url)
    }

    // MARK: - Persistence

    private func dropEmptyBatches() {
        batches.removeAll { $0.items.isEmpty }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        batches = (try? decoder.decode([ScreenshotBatch].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(batches) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
