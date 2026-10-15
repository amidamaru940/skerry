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
    init(
        fileURL: URL?,
        batchGap: @escaping () -> TimeInterval,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.fileURL = fileURL
        self.batchGap = batchGap
        self.fileExists = fileExists
        load()
        pruneMissingFiles()
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

    /// Drops screenshots whose files no longer exist.
    func pruneMissingFiles() {
        var changed = false
        for index in batches.indices {
            let before = batches[index].items.count
            batches[index].items.removeAll { !fileExists($0.path) }
            changed = changed || batches[index].items.count != before
        }
        let countBefore = batches.count
        dropEmptyBatches()
        if changed || batches.count != countBefore { save() }
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
