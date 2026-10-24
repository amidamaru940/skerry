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
    private var started = false
    /// Clipboard screenshots are collected from launch: they need no folder,
    /// so they do not wait for the screenshot folder's first look (§5.8).
    private var clipboardPartStarted = false
    /// The folder is being looked at, off the main thread, before start().
    private var lookingAtFolder = false
    /// The last folder looked at off the main thread: macOS has answered for it.
    private var answeredFolder: URL?

    /// Where the app's batches are saved; there once a screenshot was collected.
    nonisolated static var batchesFile: URL {
        AppDataDirectory.folder("Screenshots").appendingPathComponent("batches.json")
    }

    private convenience init() {
        self.init(store: ScreenshotBatchStore(
            fileURL: Self.batchesFile,
            batchGap: { TimeInterval(Defaults[.screenshotBatchGapMinutes]) * 60 },
            // Created by the first island view, on the main thread at launch:
            // start() prunes, once the screenshot folder is answered for.
            pruneOnLoad: false
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

    /// At launch: only once the screenshot folder has been looked at after
    /// the person asked for screenshots, and only while it is the folder
    /// macOS answered for then. The folder is usually the Desktop, and the
    /// first look at it brings up a macOS prompt (§5.8); a folder moved
    /// while Skerry was not running waits for the next use of screenshots.
    /// An install that ran an earlier build has the flag for any folder
    /// (`migrateFolderFirstTouch`).
    func startAtLaunch() {
        // With the folder not asked for yet (a fresh install, onboarding
        // skipped), ⌃⇧⌘4 still lands in a batch: the history leaves such a
        // picture to the batches whenever both switches are on.
        startClipboardCollecting()
        guard FolderFirstTouch.launchLooksAtScreenshotFolder(
            ScreenshotLocation.current(),
            touched: Defaults[.screenshotFolderTouched],
            touchedPath: Defaults[.screenshotFolderTouchedPath]
        ) else { return }
        lookAtFolderThenStart()
    }

    /// The person asked for screenshots: «Continue» on onboarding step 2
    /// with Screenshots on, a click on the Screenshots segment, or collecting
    /// turned on in Settings. macOS may ask for the folder now; once it has
    /// answered, later launches start on their own while the folder stays
    /// where it is. Nothing once started.
    func startOnFirstUse() {
        lookAtFolderThenStart()
    }

    /// «Use ~/Screenshots» in Settings and «Сохранять в ~/Screenshots» on the
    /// island's «Нет доступа к папке», each after its question: macOS saves
    /// screenshots to a folder it does not guard, the folder is looked at
    /// again, and collecting starts there (the person asked). False when the
    /// setting could not be changed.
    @discardableResult
    func useRecommendedFolder() -> Bool {
        let changed = ScreenshotSystemSettings.useFolder(ScreenshotLocation.recommendedFolder())
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.refreshFolder()
            // Asking for screenshots too, in a folder macOS does not guard.
            if changed, !ScreenshotLocation.isDesktopOrDocuments(ScreenshotLocation.current()) {
                self.startOnFirstUse()
            }
        }
        return changed
    }

    /// ⌃⌥⌘S (Buffer v3): «Буфер» moves to «Снимки». The person asked for
    /// screenshots, so their folder may be looked at now (§5.8).
    func openShotsByRequest() {
        BufferTabState.shared.segment = .screenshots
        startOnFirstUse()
    }

    /// The first look at a guarded folder waits for the person's answer, so
    /// it is taken off the main thread (ProtectedFolder). A refused folder
    /// then reads as `canReadFolder == false`.
    private func lookAtFolderThenStart() {
        // Looking at the folder is what asks for it; a test host must not
        // (see AppRuntimeEnvironment.mayAskForPermissions).
        guard AppRuntimeEnvironment.mayAskForPermissions, !started, !lookingAtFolder else { return }
        lookingAtFolder = true
        let folder = ScreenshotLocation.current()
        ProtectedFolder.touch(folder) { [weak self] in
            Self.noteAnswered(folder)
            guard let self else { return }
            self.lookingAtFolder = false
            self.answeredFolder = folder
            self.start()
        }
    }

    /// macOS has answered for `folder`, granted or refused: later launches
    /// may look at it again, and at no other folder (`startAtLaunch`).
    private static func noteAnswered(_ folder: URL) {
        Defaults[.screenshotFolderTouched] = true
        Defaults[.screenshotFolderTouchedPath] = FolderFirstTouch.touchedPath(
            Defaults[.screenshotFolderTouchedPath], afterAnswerFor: folder)
    }

    private func start() {
        guard !started else { return }
        started = true
        // Already running since launch, as a rule; once only.
        startClipboardCollecting()
        store.pruneMissingFiles()
        Defaults.publisher(.enableScreenshotShelf)
            .sink { [weak self] change in self?.setWatching(change.newValue) }
            .store(in: &cancellables)
        Defaults.publisher(.collectScreenRecordings, options: [])
            .sink { [weak self] _ in self?.setWatching(Defaults[.enableScreenshotShelf]) }
            .store(in: &cancellables)
        ClipboardShotLog.note("screenshot manager started")
        // The screenshot folder can change in System Settings or Screenshot.app,
        // and a refused folder can be allowed there. Looked at when it can
        // matter -- another app comes forward (the person was in Settings or
        // Screenshot.app), the person is back at the Mac, the Clipboard tab
        // opens -- instead of every 30 s (upstream of this change, the timer
        // also re-created the Spotlight query each time a folder was refused).
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshFolderLocation() }
            .store(in: &cancellables)
        // Back at the Mac: `refreshOnLook`, subscribed with the clipboard
        // part, since launch.
    }

    /// Clipboard screenshots, collected while both switches are on. The
    /// clipboard is not a folder: nothing here looks at the screenshot
    /// folder, so this runs from launch. Nothing once started.
    private func startClipboardCollecting() {
        guard !clipboardPartStarted else { return }
        clipboardPartStarted = true
        // Temporary clipboard screenshots do not outlive the app; their
        // entries go with them. Only those paths are looked at.
        TemporaryClipboardShots.removeAll()
        pruneGoneClipboardShots()
        // Applied at once: the combined publisher never delivered its first
        // value, so the collector never started.
        applyClipboardCollecting()
        Defaults.publisher(.collectClipboardScreenshots, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyClipboardCollecting() }
            .store(in: &cancellables)
        Defaults.publisher(.enableScreenshotShelf, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyClipboardCollecting() }
            .store(in: &cancellables)
        // Back at the Mac: temporary clipboard shots older than a day go,
        // whether or not the folder was ever asked for (the Settings line
        // promises a day). One event per return, nothing while idle.
        ActivityGate.shared.publisher(for: .userPresent)
            .dropFirst()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshOnLook() }
            .store(in: &cancellables)
    }

    /// Drops batch entries of temporary clipboard screenshots whose files
    /// are gone; saved screenshots are not looked at.
    private func pruneGoneClipboardShots() {
        store.pruneMissingFiles(only: { TemporaryClipboardShots.holds(path: $0) })
    }

    /// The Clipboard tab opened, or the person is back: drop screenshots
    /// whose files are gone, temporary clipboard ones older than a day
    /// included, and follow a moved folder. Before the folder was asked
    /// for, only the temporary clipboard ones are looked at.
    func refreshOnLook() {
        TemporaryClipboardShots.removeExpired()
        if !started { pruneGoneClipboardShots() }
        refreshFolder()
    }

    /// Only the folder setting: cheap enough for every app activation.
    private func refreshFolderLocation() {
        guard started, Defaults[.enableScreenshotShelf] else { return }
        if ScreenshotLocation.current() != folder {
            setWatching(true)
        }
    }

    // MARK: - Watching

    private func setWatching(_ enabled: Bool) {
        watcher?.stop()
        watcher = nil
        guard enabled else { return }
        let current = ScreenshotLocation.current()
        if current != answeredFolder, AppRuntimeEnvironment.mayAskForPermissions {
            // The folder moved (System Settings, Screenshot.app), maybe into
            // another one macOS guards: the first look there waits for an
            // answer, so it is taken off the main thread before watching.
            ProtectedFolder.touch(current) { [weak self] in
                Self.noteAnswered(current)
                guard let self else { return }
                self.answeredFolder = current
                self.setWatching(Defaults[.enableScreenshotShelf])
            }
            return
        }
        folder = current
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
    /// Before start() only the setting is re-read, for Settings to show:
    /// looking at the folder is what asks for it.
    func refreshFolder() {
        guard started else {
            folder = ScreenshotLocation.current()
            return
        }
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
            // Buffer v3: on «Все», where the new batch's film and its key are,
            // unless «Снимки» is already showing them.
            let buffer = BufferTabState.shared
            let segment = BufferLayout.segmentAfterCapture(buffer.segment)
            if buffer.segment != segment { buffer.segment = segment }
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

    /// The screenshots «Буфер» shows: all of them, or only the clipboard
    /// ones while the screenshot folder cannot be read.
    var shownItemIDs: Set<String> {
        let shown = ScreenshotBatchPanel.visibleBatches(store.batches, onlyClipboardShots: !canReadFolder)
        return Set(shown.flatMap(\.items).map(\.id))
    }

    /// The Buffer's trash: the shown screenshots leave «Буфер» at once, and
    /// stay restorable until `finishTakeOut`.
    func takeOutShown() -> ScreenshotBatchStore.Removal {
        let removal = store.takeOut(shownItemIDs)
        selection.subtract(removal.items.map(\.id))
        return removal
    }

    func restore(_ removal: ScreenshotBatchStore.Removal) {
        store.restore(removal)
    }

    /// The offer is over: temporary clipboard screenshots go. Saved ones
    /// only left «Буфер»; their files are never touched from here, whatever
    /// the Trash setting (that asks first, per batch).
    func finishTakeOut(_ removal: ScreenshotBatchStore.Removal) {
        // By the path's text alone: a saved one on the Desktop is never looked at.
        TemporaryClipboardShots.remove(removal.items.filter { TemporaryClipboardShots.holds(path: $0.path) }.map(\.url))
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
            // Only the batch forgets them; the files stay. A chat or browser
            // (Chromium, Electron) gets just the paths at the drop and reads
            // the files later, at upload or on Send -- deleting or trashing
            // them here broke the very drop it was counting.
            let removed = store.remove(draggedIDs)
            selection.subtract(removed.map(\.id))
        }
        draggedIDs = []
    }

    // MARK: - Copy, Finder, Markup

    /// Puts the selected screenshots on the clipboard (paste them into a chat
    /// with ⌘V). Marked as the app's own write, so the clipboard history does
    /// not record it.
    @discardableResult
    func copySelected(to pasteboard: NSPasteboard = .general) -> Task<Int, Never> {
        copy(selectedURLs, to: pasteboard)
    }

    /// Puts the screenshots on the clipboard, one item each with the file
    /// and its picture (`ScreenshotPasteboard`). The pictures are read and
    /// the large ones downscaled off the main thread one at a time, so the
    /// clipboard is written a moment later; the task answers how many went
    /// (0 when the files are gone, and then the clipboard is left as it
    /// was). A newer copy or paste, or a history entry or colour copied
    /// meanwhile, stops it (`ClipboardPaster.yieldClipboard`).
    @discardableResult
    func copy(_ urls: [URL], to pasteboard: NSPasteboard = .general) -> Task<Int, Never> {
        let urls = ScreenshotPasteboard.existing(urls)
        return ClipboardPaster.startCopy {
            guard !urls.isEmpty else { return 0 }
            return await ScreenshotPasteboard.copy(urls, to: pasteboard)
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
    /// Several go one by one, each with its own ⌘V (Claude, Chrome and
    /// Telegram attach one picture per paste); one goes as before. The
    /// clipboard is left holding the last screenshot alone. When none of
    /// the files is there any more, nothing is closed or pressed
    /// (`.nothingCopied`). When the target leaves the front or an island
    /// opens mid-way, the rest are copied together and `onStopped` gets
    /// their count, for a "press ⌘V" hint.
    @MainActor
    @discardableResult
    func paste(batch: ScreenshotBatch, pasteboard: NSPasteboard = .general, target: NSRunningApplication? = nil,
               isIslandOpen: @escaping @MainActor () -> Bool = { false },
               onStopped: @escaping @MainActor (Int) -> Void = { _ in },
               closeIsland: () -> Void) -> ClipboardPaster.Result {
        let urls = ScreenshotPasteboard.existing(pasteURLs(for: batch))
        return ClipboardPaster.deliverOneByOne(
            count: urls.count,
            target: target,
            isIslandOpen: isIslandOpen,
            closeIsland: closeIsland,
            prepare: { await ScreenshotPasteboard.prepare(urls[$0]) },
            writeOne: { ScreenshotPasteboard.write([$0], to: pasteboard) },
            writeTogether: { await ScreenshotPasteboard.copy(Array(urls[$0]), to: pasteboard) },
            onStopped: onStopped
        )
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
