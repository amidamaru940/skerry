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
import Combine
import Defaults

/// Collects new screenshots into batches and runs the batch actions.
@MainActor
final class ScreenshotShelfManager: ObservableObject {
    static let shared = ScreenshotShelfManager()

    /// Shown briefly in the closed island when a screenshot arrives.
    struct Flash: Equatable {
        let id = UUID()
        let url: URL
        let count: Int
    }

    let store: ScreenshotBatchStore
    @Published var selection: Set<String> = []
    @Published private(set) var flash: Flash?
    @Published private(set) var folder: URL
    /// False when macOS refuses access to the screenshot folder (Desktop and
    /// Documents need a privacy permission; ~/Screenshots does not).
    @Published private(set) var canReadFolder = true
    /// True while screenshots are being dragged out of the grid.
    @Published private(set) var isDragging = false

    private let launchDate = Date()
    private var watcher: ScreenshotWatcher?
    private var clipboardCollector: ClipboardScreenshotCollector?
    private var cancellables = Set<AnyCancellable>()
    private var flashWork: DispatchWorkItem?
    private var locationTimer: Timer?
    private var started = false

    private convenience init() {
        self.init(store: ScreenshotBatchStore(
            fileURL: AppDataDirectory.folder("Screenshots").appendingPathComponent("batches.json"),
            batchGap: { TimeInterval(Defaults[.screenshotBatchGapMinutes]) * 60 }
        ))
    }

    /// Tests pass their own store; the app uses `shared`.
    init(store: ScreenshotBatchStore) {
        self.store = store
        folder = ScreenshotLocation.current()
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Called once at launch.
    func start() {
        guard !started else { return }
        started = true
        // Temporary clipboard screenshots do not outlive the app.
        TemporaryClipboardShots.removeAll()
        store.pruneMissingFiles()
        Defaults.publisher(.enableScreenshotShelf)
            .sink { [weak self] change in self?.setWatching(change.newValue) }
            .store(in: &cancellables)
        Defaults.publisher(.collectScreenRecordings, options: [])
            .sink { [weak self] _ in self?.setWatching(Defaults[.enableScreenshotShelf]) }
            .store(in: &cancellables)
        // Clipboard screenshots are collected only while screenshot collecting
        // is on too. Applied at once here: the combined publisher never
        // delivered its first value, so the collector never started.
        ClipboardShotLog.note("screenshot manager started")
        applyClipboardCollecting()
        Defaults.publisher(.collectClipboardScreenshots, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyClipboardCollecting() }
            .store(in: &cancellables)
        Defaults.publisher(.enableScreenshotShelf, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyClipboardCollecting() }
            .store(in: &cancellables)
        // The screenshot folder can change in System Settings or Screenshot.app.
        locationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFolder()
                // Temporary clipboard screenshots last a day at most.
                if TemporaryClipboardShots.removeExpired() { self?.store.pruneMissingFiles() }
            }
        }
    }

    // MARK: - Watching

    private func setWatching(_ enabled: Bool) {
        watcher?.stop()
        watcher = nil
        guard enabled else { return }
        folder = ScreenshotLocation.current()
        let watcher = ScreenshotWatcher(folder: folder, startDate: launchDate,
                                        includeRecordings: Defaults[.collectScreenRecordings]) { [weak self] url, date in
            Task { @MainActor in self?.didCapture(url, at: date) }
        }
        // Listing the folder is also what makes macOS ask for Desktop/Documents access.
        canReadFolder = watcher.canReadFolder
        watcher.start()
        self.watcher = watcher
    }

    /// Re-reads the screenshot folder and restarts watching when it moved.
    func refreshFolder() {
        store.pruneMissingFiles()
        guard Defaults[.enableScreenshotShelf] else { return }
        if ScreenshotLocation.current() != folder || !canReadFolder {
            setWatching(true)
        }
    }

    private func applyClipboardCollecting() {
        setCollectingClipboard(Defaults[.enableScreenshotShelf] && Defaults[.collectClipboardScreenshots])
    }

    private func setCollectingClipboard(_ enabled: Bool) {
        ClipboardShotLog.note("collect clipboard screenshots: \(enabled)")
        if enabled {
            if clipboardCollector == nil {
                clipboardCollector = ClipboardScreenshotCollector { [weak self] url, date in
                    Task { @MainActor in self?.didCapture(url, at: date) }
                }
            }
            clipboardCollector?.start()
        } else {
            clipboardCollector?.stop()
        }
    }

    /// The presenting state that keeps the flash and the tab switch quiet; replaced in tests.
    var presentation: ScreenPresentation = .shared

    func didCapture(_ url: URL, at date: Date) {
        guard store.add(url, capturedAt: date) else { return }
        // While the screen is shared, the screenshot is collected without a word.
        guard !presentation.isHidingContent else { return }
        showFlash(for: url)
        // Screenshots live in the Clipboard tab (step D4).
        if Defaults[.openScreenshotsOnNewScreenshot], NotchTabLayout.isVisible(.clipboard) {
            DynamicIslandViewCoordinator.shared.currentView = .clipboard
        }
    }

    private func showFlash(for url: URL) {
        flashWork?.cancel()
        flash = Flash(url: url, count: store.currentBatch?.items.count ?? 1)
        let work = DispatchWorkItem { [weak self] in self?.flash = nil }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    // MARK: - Selection

    /// The last plainly or Cmd-clicked screenshot, where a Shift-click range starts.
    private var anchorID: String?

    /// Screenshots in display order: newest batch first, newest first within a batch.
    var displayOrder: [ScreenshotItem] { store.batches.flatMap(\.newestFirst) }

    /// Click (and Cmd-click): add it to or remove it from the selection.
    /// Shift-click (`range`): add every screenshot between the anchor and it.
    /// Double-click: keep it chosen (the caller opens Quick Look).
    func click(_ item: ScreenshotItem, extend: Bool, range: Bool = false, double: Bool = false) {
        if double {
            // The first click of the pair already chose it: keep it chosen.
            if !selection.contains(item.id) { selection.insert(item.id) }
            anchorID = item.id
            return
        }
        if range, let anchorID,
           let from = displayOrder.firstIndex(where: { $0.id == anchorID }),
           let to = displayOrder.firstIndex(where: { $0.id == item.id }) {
            selection.formUnion(displayOrder[min(from, to)...max(from, to)].map(\.id))
            return
        }
        // Every click adds or removes, like ticks (owner's choice, 15.10);
        // Cmd-click does the same, Shift-click a range.
        _ = extend
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        anchorID = item.id
    }

    func selectAll() {
        selection = Set(store.allItems.map(\.id))
    }

    func isFullySelected(_ batch: ScreenshotBatch) -> Bool {
        !batch.items.isEmpty && batch.items.allSatisfy { selection.contains($0.id) }
    }

    /// "Select All" for one batch, or "Deselect" when all of it is chosen.
    func toggleSelectAll(in batch: ScreenshotBatch) {
        let ids = Set(batch.items.map(\.id))
        if isFullySelected(batch) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    func clearSelection() {
        selection.removeAll()
    }

    /// Selected files in capture order.
    var selectedURLs: [URL] { store.fileURLs(for: selection) }

    /// What a drag of `item` carries: the whole selection when the item is
    /// part of it, otherwise just this item.
    func dragURLs(startingAt item: ScreenshotItem) -> [URL] {
        selection.contains(item.id) ? selectedURLs : [item.url]
    }

    // MARK: - Removing (files stay unless the Trash option is on)

    func removeSelected() {
        finishRemoval(store.remove(selection))
    }

    func keepSelected() {
        guard !selection.isEmpty else { return }
        finishRemoval(store.keepOnly(selection))
    }

    func clear(batchID: UUID) {
        finishRemoval(store.clear(batchID: batchID))
    }

    /// A removal that would move files to the Trash, waiting for a yes.
    enum PendingRemoval: Equatable {
        case items(Set<String>)
        case batch(UUID, count: Int)

        var count: Int {
            switch self {
            case .items(let ids): return ids.count
            case .batch(_, let count): return count
            }
        }
    }

    /// Set while the Trash option is on and a removal waits for a yes.
    @Published var pendingRemoval: PendingRemoval?

    /// With "move originals to the Trash" on, files would go to the Trash:
    /// ask first (they went without a word). Otherwise only the batch
    /// forgets them, at once.
    func requestRemoval(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        if movesToTrash(ids) {
            pendingRemoval = .items(ids)
        } else {
            finishRemoval(store.remove(ids))
        }
    }

    func requestClear(_ batch: ScreenshotBatch) {
        if movesToTrash(Set(batch.items.map(\.id))) {
            pendingRemoval = .batch(batch.id, count: batch.items.count)
        } else {
            clear(batchID: batch.id)
        }
    }

    func confirmPendingRemoval() {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        switch pending {
        case .items(let ids): finishRemoval(store.remove(ids))
        case .batch(let id, _): clear(batchID: id)
        }
    }

    private func finishRemoval(_ removed: [ScreenshotItem]) {
        selection.subtract(removed.map(\.id))
        // A temporary clipboard screenshot has no original: it just goes.
        let temporary = removed.filter { TemporaryClipboardShots.isTemporary($0.url) }
        TemporaryClipboardShots.remove(temporary.map(\.url))
        guard Defaults[.screenshotMoveOriginalsToTrash] else { return }
        for item in removed where !TemporaryClipboardShots.isTemporary(item.url) {
            try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        }
    }

    /// Only originals go to the Trash: temporary clipboard screenshots need
    /// no question.
    private func movesToTrash(_ ids: Set<String>) -> Bool {
        Defaults[.screenshotMoveOriginalsToTrash]
            && ids.contains { !TemporaryClipboardShots.isTemporary(URL(fileURLWithPath: $0)) }
    }

    // MARK: - Dragging out

    private var draggedIDs: Set<String> = []

    func dragBegan(with urls: [URL]) {
        isDragging = true
        draggedIDs = Set(urls.map { $0.standardizedFileURL.path })
    }

    /// `succeeded` is false when the drop was cancelled or refused.
    func dragEnded(succeeded: Bool) {
        isDragging = false
        if succeeded, Defaults[.screenshotRemoveAfterDrag] {
            finishRemoval(store.remove(draggedIDs))
        }
        draggedIDs = []
    }

    // MARK: - Copy, Finder, Markup

    /// Puts the selected files on the clipboard (paste them into a chat with
    /// ⌘V); a single screenshot also goes as a picture. Marked as the app's own
    /// write, so the clipboard history does not record it.
    func copySelected(to pasteboard: NSPasteboard = .general) {
        copy(selectedURLs, to: pasteboard)
    }

    func copy(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        guard !urls.isEmpty else { return }
        ClipboardOwnWrites.write(to: pasteboard) { pasteboard in
            pasteboard.writeObjects(urls as [NSURL])
            if urls.count == 1, let image = NSImage(contentsOf: urls[0]) {
                pasteboard.writeObjects([image])
            }
        }
    }

    /// What "Paste" takes from a batch: the screenshots selected in it, or
    /// the whole batch when none is, in capture order.
    func pasteURLs(for batch: ScreenshotBatch) -> [URL] {
        let chosen = batch.items.filter { selection.contains($0.id) }
        return (chosen.isEmpty ? batch.items : chosen).map(\.url)
    }

    /// Copies the batch (or its selected screenshots) and pastes it into
    /// the app the user was working in: one click from screenshots to chat.
    @MainActor
    @discardableResult
    func paste(batch: ScreenshotBatch, pasteboard: NSPasteboard = .general, target: NSRunningApplication? = nil,
               closeIsland: () -> Void) -> ClipboardPaster.Result {
        let urls = pasteURLs(for: batch)
        return ClipboardPaster.deliver(target: target, closeIsland: closeIsland) {
            copy(urls, to: pasteboard)
        }
    }

    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let share = QuickShareService.shared
        share.ensureDiscovered()
        if let airDrop = share.availableProviders.first(where: { $0.id == "AirDrop" }) {
            Task { await share.shareFilesOrText(urls, using: airDrop, from: nil) }
        } else {
            AirDrop(files: urls).begin()
        }
    }

    /// Removes the selected screenshots of `batch` from it (asking first
    /// when that moves files to the Trash).
    func removeSelected(in batch: ScreenshotBatch) {
        requestRemoval(Set(batch.items.map(\.id)).intersection(selection))
    }

    func selectedCount(in batch: ScreenshotBatch) -> Int {
        batch.items.filter { selection.contains($0.id) }.count
    }

    /// Opens the screenshots in the system Markup editor, one after another
    /// (`MarkupQueue`); in Preview when Markup cannot take them.
    func markup(_ urls: [URL]) {
        guard !urls.isEmpty, !MarkupQueue.shared.start(urls),
              let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }
}
