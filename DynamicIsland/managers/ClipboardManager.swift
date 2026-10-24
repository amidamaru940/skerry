/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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
import Combine
import Foundation
import UniformTypeIdentifiers
import Defaults

// Clipboard item data structure
struct ClipboardItem: Identifiable, Codable {
    let id = UUID()
    let type: ClipboardItemType
    let timestamp: Date
    let preview: String
    var isPinned: Bool = false
    /// Bundle identifier of the app that was in front when this was copied.
    var sourceBundleID: String?

    /// Only 4 to 8 digits: what verification codes look like.
    var isOneTimeCode: Bool {
        guard type == .text, let text = stringData?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return (4...8).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
    
    /// Image bytes for items captured while history persistence is off.
    ///
    /// Held here rather than written to `clipboardDataDirectory`, because the
    /// setting promises nothing reaches disk — and a PNG of whatever you copied
    /// is the most sensitive thing the clipboard handles. Keyed by item id and
    /// pruned as items leave, so it stays bounded by the history size.
    private static var inMemoryImages: [UUID: Data] = [:]
    private static let inMemoryImagesLock = NSLock()

    static func pruneInMemoryImages(keeping ids: Set<UUID>) {
        inMemoryImagesLock.lock()
        defer { inMemoryImagesLock.unlock() }
        inMemoryImages = inMemoryImages.filter { ids.contains($0.key) }
    }

    static func storeInMemoryImage(_ data: Data, for id: UUID) {
        inMemoryImagesLock.lock()
        defer { inMemoryImagesLock.unlock() }
        inMemoryImages[id] = data
    }

    static func inMemoryImage(for id: UUID) -> Data? {
        inMemoryImagesLock.lock()
        defer { inMemoryImagesLock.unlock() }
        return inMemoryImages[id]
    }

    // Store different types of data - avoid large binary data in UserDefaults
    let stringData: String?
    var imageFileName: String? // Store filename instead of data
    let fileURLs: [String]?
    let rtfData: Data? // RTF is typically small, so we can keep this
    
    init(stringData: String, type: ClipboardItemType) {
        self.stringData = stringData
        self.imageFileName = nil
        self.fileURLs = nil
        self.rtfData = nil
        self.type = type
        self.timestamp = Date()
        self.preview = ClipboardItem.generatePreview(stringData: stringData, type: type)
    }
    
    init(imageData: Data) {
        self.stringData = nil
        self.fileURLs = nil
        self.rtfData = nil
        self.type = .image
        self.timestamp = Date()
        
        let sizeDescription = ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)

        guard Defaults[.persistClipboardHistory] else {
            // Session-only: keep the bytes in memory so the image never lands
            // in clipboardDataDirectory.
            self.imageFileName = nil
            self.preview = "Image (\(sizeDescription))"
            ClipboardItem.storeInMemoryImage(imageData, for: id)
            return
        }

        // Save image data to temporary file instead of storing in UserDefaults
        let fileName = "clipboard_image_\(UUID().uuidString).png"
        let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL)
            self.imageFileName = fileName
            self.preview = "Image (\(sizeDescription))"
        } catch {
            print("Failed to save image data: \(error)")
            self.imageFileName = nil
            self.preview = "Image (failed to save)"
        }
    }
    
    init(fileURLs: [String]) {
        self.stringData = nil
        self.imageFileName = nil
        self.fileURLs = fileURLs
        self.rtfData = nil
        self.type = .file
        self.timestamp = Date()
        
        if fileURLs.count == 1, let url = URL(string: fileURLs.first!) {
            self.preview = url.lastPathComponent
        } else {
            self.preview = "\(fileURLs.count) files"
        }
    }
    
    init(rtfData: Data, plainText: String) {
        // RTF data is typically small, so we can keep it in UserDefaults
        self.stringData = plainText
        self.imageFileName = nil
        self.fileURLs = nil
        self.rtfData = rtfData.count > 100000 ? nil : rtfData // Skip very large RTF files
        self.type = .rtf
        self.timestamp = Date()
        self.preview = String(plainText.prefix(50))
    }
    
    // Helper to get image data from memory or file
    func getImageData() -> Data? {
        if let inMemory = ClipboardItem.inMemoryImage(for: id) { return inMemory }
        guard let fileName = imageFileName else { return nil }
        let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }
    
    // Helper to check if this item has the same content as another
    func isSameContent(as other: ClipboardItem) -> Bool {
        return stringData == other.stringData &&
               imageFileName == other.imageFileName &&
               fileURLs == other.fileURLs &&
               type == other.type
    }
    
    static func generatePreview(stringData: String, type: ClipboardItemType) -> String {
        switch type {
        case .text:
            return String(stringData.prefix(50))
        case .url:
            if let url = URL(string: stringData) {
                return url.lastPathComponent.isEmpty ? url.host ?? stringData : url.lastPathComponent
            }
            return String(stringData.prefix(50))
        case .file:
            if let url = URL(string: stringData) {
                return url.lastPathComponent
            }
            return "File"
        case .image:
            return "Image"
        case .rtf:
            return String(stringData.prefix(50))
        case .unknown:
            return String(stringData.prefix(50))
        }
    }
}

enum ClipboardItemType: String, CaseIterable, Codable {
    case text = "text"
    case url = "url"
    case file = "file"
    case image = "image"
    case rtf = "rtf"
    case unknown = "unknown"
    
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .file: return "doc"
        case .image: return "photo"
        case .rtf: return "doc.richtext"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var displayName: String {
        switch self {
        case .text: return String(localized: "Text")
        case .url: return String(localized: "URL")
        case .file: return String(localized: "File")
        case .image: return String(localized: "Image")
        case .rtf: return String(localized: "Rich Text")
        case .unknown: return String(localized: "Unknown")
        }
    }
}

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var clipboardHistory: [ClipboardItem] = []
    @Published var pinnedItems: [ClipboardItem] = []
    @Published var isMonitoring: Bool = false
    @Published private(set) var lastCopiedItemDate: Date?
    /// True while a clipboard item is being dragged out; keeps the notch open
    /// (see `shouldPreventAutoClose`). SwiftUI `.onDrag` has no drag-end callback,
    /// so a bounded timeout releases it in case a drop is never observed.
    /// A card is being dragged out of the Clipboard tab. Set and cleared by
    /// the card's AppKit dragging source, which reports the real end.
    @Published private(set) var isDraggingItem: Bool = false

    /// Our place in the shared `changeCount` look while monitoring.
    private var watcherToken: UUID?
    private var lastChangeCount: Int = 0
    private var persistenceCancellable: AnyCancellable?
    private var pinnedPersistenceCancellable: AnyCancellable?
    private var autoClearCancellable: AnyCancellable?
    private var expiryTimer: Timer?
    
    // Use configurable history size from settings
    private var maxHistoryItems: Int {
        return Defaults[.clipboardHistorySize]
    }
    
    // Computed properties for filtered lists
    var regularHistory: [ClipboardItem] {
        clipboardHistory.filter { !$0.isPinned }
    }
    
    var pinnedHistory: [ClipboardItem] {
        pinnedItems
    }
    
    // Directory for storing clipboard data files
    static var clipboardDataDirectory: URL { directoryOverride ?? defaultDataDirectory }

    /// Where the tests point this instead of the app's real data folder.
    ///
    /// The transition tests turn persistence off, which deletes every unpinned
    /// image file in this directory -- so with no override, running the suite
    /// deletes the clipboard images of whoever ran it.
    static var directoryOverride: URL?

    /// Upstream wrote these PNGs to the iCloud-synced ~/Documents/ClipboardData.
    static let defaultDataDirectory: URL = AppDataDirectory.folder("ClipboardData")
    
    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        loadHistoryFromDefaults()
        cleanupOldFiles()
        observeHistoryPersistence()
        observePinnedPersistence()
        purgeExpiredItems()
        scheduleAutoClear()
    }

    /// Runs the age-based cleanup when the next item is due and whenever its
    /// setting changes, independent of whether the pasteboard is being
    /// watched. One timer for the earliest expiry, not a minute tick: nothing
    /// wakes the app while nothing is due. A timer due during sleep fires on
    /// wake.
    private func scheduleAutoClear() {
        autoClearCancellable = Defaults.publisher(keys: .clipboardAutoClearHours, .clipboardOneTimeCodeExpiry, options: [])
            .sink { [weak self] in
                DispatchQueue.main.async { self?.purgeExpiredItems() }
            }
    }

    /// When the next unpinned item expires under the current settings, or nil
    /// when none ever will.
    static func nextExpiry(of items: [ClipboardItem], autoClearHours: Int, removeCodes: Bool) -> Date? {
        items.compactMap { item -> Date? in
            var due: [Date] = []
            if autoClearHours > 0 { due.append(item.timestamp.addingTimeInterval(Double(autoClearHours) * 3600)) }
            if removeCodes && item.isOneTimeCode { due.append(item.timestamp.addingTimeInterval(oneTimeCodeLifetime)) }
            return due.min()
        }.min()
    }

    private func rescheduleExpiry(now: Date = Date()) {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard let due = Self.nextExpiry(of: clipboardHistory,
                                        autoClearHours: Defaults[.clipboardAutoClearHours],
                                        removeCodes: Defaults[.clipboardOneTimeCodeExpiry]) else { return }
        // A second late is fine; the tolerance lets macOS fold the wakeup in.
        let timer = Timer(fire: max(due, now).addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            self?.purgeExpiredItems()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    /// Removes history items older than `clipboardAutoClearHours` (0 keeps
    /// everything). Pinned items are an explicit request to keep something
    /// and are left alone.
    func purgeExpiredItems(now: Date = Date()) {
        let hours = Defaults[.clipboardAutoClearHours]
        let cutoff = hours > 0 ? now.addingTimeInterval(-Double(hours) * 3600) : .distantPast
        let codeCutoff = now.addingTimeInterval(-Self.oneTimeCodeLifetime)
        let removeCodes = Defaults[.clipboardOneTimeCodeExpiry]
        let expired = clipboardHistory.filter {
            $0.timestamp < cutoff || (removeCodes && $0.isOneTimeCode && $0.timestamp <= codeCutoff)
        }
        defer { rescheduleExpiry(now: now) }
        guard !expired.isEmpty else { return }

        for item in expired {
            if let fileName = item.imageFileName {
                let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        let expiredIDs = Set(expired.map { $0.id })
        clipboardHistory.removeAll { expiredIDs.contains($0.id) }
        saveHistoryToDefaults()
    }

    /// Turning persistence off has to erase what is already on disk, otherwise
    /// the setting would only stop *future* writes and leave the existing
    /// history — the very thing the user asked not to keep — sitting in
    /// UserDefaults until something happened to overwrite it.
    /// How long a one-time code stays in the history.
    static let oneTimeCodeLifetime: TimeInterval = 120

    /// Saving pinned items is a separate choice: turning it on writes them
    /// (and their pictures) to disk, turning it off erases what was written.
    private func observePinnedPersistence() {
        pinnedPersistenceCancellable = Defaults.publisher(.clipboardPersistPinned, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    for index in self.pinnedItems.indices where self.pinnedItems[index].imageFileName == nil {
                        self.pinnedItems[index].imageFileName = self.persistImageFile(for: self.pinnedItems[index].id)
                    }
                    self.savePinnedItemsToDefaults()
                } else {
                    let historyFiles = Set(self.clipboardHistory.compactMap(\.imageFileName))
                    for index in self.pinnedItems.indices {
                        guard let name = self.pinnedItems[index].imageFileName, !historyFiles.contains(name) else { continue }
                        if let data = self.pinnedItems[index].getImageData() {
                            ClipboardItem.storeInMemoryImage(data, for: self.pinnedItems[index].id)
                        }
                        try? FileManager.default.removeItem(at: ClipboardManager.clipboardDataDirectory.appendingPathComponent(name))
                        self.pinnedItems[index].imageFileName = nil
                    }
                    self.savePinnedItemsToDefaults()
                }
            }
    }

    private func observeHistoryPersistence() {
        persistenceCancellable = Defaults.publisher(.persistClipboardHistory, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    // Session-only images have no file yet; give them one so
                    // they survive the restart the user just opted into.
                    self.persistInMemoryImages()
                    self.saveHistoryToDefaults()
                    self.savePinnedItemsToDefaults()
                } else {
                    // Take the bytes into memory before the files go, or the
                    // items still on screen lose their images mid-session.
                    self.retainImagesInMemory()
                    ClipboardManager.removeStoredHistory()
                    self.removeUnpinnedImageFiles()
                }
            }
    }

    private static func removeStoredHistory() {
        UserDefaults.standard.removeObject(forKey: "ClipboardHistory")
    }

    /// Reads every history image into the in-memory store so the entries keep
    /// rendering and re-copying after their files are deleted.
    private func retainImagesInMemory() {
        for item in clipboardHistory {
            guard item.imageFileName != nil, let data = item.getImageData() else { continue }
            ClipboardItem.storeInMemoryImage(data, for: item.id)
        }
    }

    /// Gives session-only images a file on disk, so turning persistence back on
    /// keeps the images the current session captured rather than restoring
    /// entries whose picture is gone.
    private func persistInMemoryImages() {
        for index in clipboardHistory.indices where clipboardHistory[index].imageFileName == nil {
            clipboardHistory[index].imageFileName = persistImageFile(for: clipboardHistory[index].id)
        }

        guard Defaults[.clipboardPersistPinned] else { return }
        for index in pinnedItems.indices where pinnedItems[index].imageFileName == nil {
            pinnedItems[index].imageFileName = persistImageFile(for: pinnedItems[index].id)
        }
    }

    /// Deletes image files written while persistence was on, so turning the
    /// setting off does not leave PNGs of past copies behind. Files backing
    /// pinned items are kept: pinning is an explicit request to keep something,
    /// and this setting is about history.
    private func removeUnpinnedImageFiles() {
        ClipboardManager.removeUnpinnedImageFiles(
            keeping: Set(pinnedItems.compactMap { $0.imageFileName })
        )
    }

    /// Erases saved history at launch when persistence is off, without building
    /// the manager. The instance is created lazily — often not until the user
    /// opens the clipboard, sometimes never — so leaving this to `init` would
    /// let history the user asked not to keep sit on disk for the whole
    /// session.
    static func purgeStoredHistoryIfPersistenceDisabled() {
        // Pinned items are kept on disk only when that was asked for.
        if !Defaults[.clipboardPersistPinned] {
            UserDefaults.standard.removeObject(forKey: "ClipboardPinnedItems")
        }
        guard !Defaults[.persistClipboardHistory] else { return }
        removeStoredHistory()
        // The stored list was only half of it. The images it referred to are
        // separate PNGs, and this runs at launch precisely because the manager
        // is lazy -- so nothing else was going to delete them either, and the
        // pictures a user asked not to keep sat in Documents all session.
        removeUnpinnedImageFiles(keeping: storedPinnedImageFileNames())
    }

    /// The image files the *saved* pinned items refer to.
    ///
    /// Read from disk rather than from `pinnedItems`, because the purge above
    /// runs before there is a manager to ask -- which is the whole reason it
    /// is a launch step.
    private static func storedPinnedImageFileNames() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: "ClipboardPinnedItems"),
              let pinned = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return []
        }
        return Set(pinned.compactMap { $0.imageFileName })
    }

    /// Deletes every image in the data directory except the ones named.
    ///
    /// Pinning is a request to keep something regardless of the history
    /// setting, so a pinned item's file survives.
    private static func removeUnpinnedImageFiles(keeping keep: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: clipboardDataDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
    
    deinit {
        stopMonitoring()
        expiryTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        // Once a second, only while someone is at the Mac
        // (`ClipboardChangeWatcher`); upstream looked twice a second for ever.
        lastChangeCount = NSPasteboard.general.changeCount
        watcherToken = ClipboardChangeWatcher.shared.add { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        ClipboardChangeWatcher.shared.remove(watcherToken)
        watcherToken = nil
    }
    
    /// A card drag began or ended. Upstream had no end callback (SwiftUI
    /// `.onDrag`) and cleared the flag after 8 s, which let the island close
    /// under a slower drag; the cards' AppKit source reports the real end.
    func dragBegan() { isDraggingItem = true }
    func dragEnded() { isDraggingItem = false }

    /// Puts an entry back on the clipboard. The write is marked as the app's
    /// own (the history does not record it again) and the same entry moves to
    /// the top of the history instead of a duplicate appearing.
    /// `plainText` drops formatting, links and pictures: only text goes.
    /// A screenshot paste or copy under way stops first, so it does not
    /// overwrite this copy a moment later.
    func copyToClipboard(_ item: ClipboardItem, plainText: Bool = false, to pasteboard: NSPasteboard = .general) {
        ClipboardPaster.yieldClipboardFromAnyThread()
        ClipboardOwnWrites.write(to: pasteboard) { pasteboard in
            if plainText {
                if let text = item.stringData ?? item.fileURLs?.compactMap({ URL(string: $0)?.path }).joined(separator: "\n") {
                    pasteboard.setString(text, forType: .string)
                }
            } else {
                writeContents(of: item, to: pasteboard)
            }
        }
        promote(item)
    }

    /// Moves a history entry to the top, keeping its identity.
    func promote(_ item: ClipboardItem) {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == item.id }), index > 0 else { return }
        let entry = clipboardHistory.remove(at: index)
        clipboardHistory.insert(entry, at: 0)
        saveHistoryToDefaults()
    }

    private func writeContents(of item: ClipboardItem, to pasteboard: NSPasteboard) {
        switch item.type {
        case .text, .url:
            if let stringData = item.stringData {
                pasteboard.setString(stringData, forType: .string)
            }
        case .image:
            if let imageData = item.getImageData() {
                pasteboard.setData(imageData, forType: .png)
            }
        case .file:
            if let fileURLs = item.fileURLs {
                let urls = fileURLs.compactMap { URL(string: $0) }
                pasteboard.writeObjects(urls as [NSPasteboardWriting])
            }
        case .rtf:
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            // Also set plain text as fallback
            if let stringData = item.stringData {
                pasteboard.setString(stringData, forType: .string)
            }
        case .unknown:
            if let stringData = item.stringData {
                pasteboard.setString(stringData, forType: .string)
            }
        }
    }
    
    func deleteItem(_ item: ClipboardItem) {
        // Clean up associated files
        if let fileName = item.imageFileName {
            let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        clipboardHistory.removeAll { $0.id == item.id }
        saveHistoryToDefaults()
    }
    
    func clearHistory() {
        // Clean up all associated files
        for item in clipboardHistory {
            if let fileName = item.imageFileName {
                let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        clipboardHistory.removeAll()
        saveHistoryToDefaults()
    }
    
    // MARK: Removing with «Отменить»

    /// Entries taken out of the lists for a few seconds of «Отменить»: their
    /// image files stay on disk (and in-memory pictures are held here) until
    /// `finishRemoval` or a restore. A file left behind by a quit in between
    /// is an unreferenced one, which the next launch deletes.
    struct Removal {
        struct Entry {
            let index: Int
            let item: ClipboardItem
        }

        fileprivate(set) var history: [Entry] = []
        fileprivate(set) var pinned: [Entry] = []
        fileprivate var pictures: [UUID: Data] = [:]

        var count: Int { history.count + pinned.count }
        var isEmpty: Bool { count == 0 }
        var items: [ClipboardItem] { (pinned + history).map(\.item) }
    }

    /// Takes one entry out of the history or the pinned items (a pinned one
    /// goes whole, as `delete` did: unpinned, then deleted), keeping what
    /// `restore` needs to put it back where it was.
    func remove(_ item: ClipboardItem) -> Removal {
        var removal = Removal()
        if let index = pinnedItems.firstIndex(where: { $0.id == item.id }) {
            removal.pinned.append(.init(index: index, item: pinnedItems.remove(at: index)))
        }
        if let index = clipboardHistory.firstIndex(where: { $0.id == item.id }) {
            removal.history.append(.init(index: index, item: clipboardHistory.remove(at: index)))
        }
        holdPictures(of: &removal)
        saveHistoryToDefaults()
        if !removal.pinned.isEmpty { savePinnedItemsToDefaults() }
        rescheduleExpiry()
        return removal
    }

    /// Takes the recent entries `filter` shows out (pinned ones stay), for
    /// «Отменить».
    func removeHistory(matching filter: ClipboardFilter = .all) -> Removal {
        var removal = Removal()
        removal.history = clipboardHistory.enumerated()
            .filter { filter.matches($0.element.type) }
            .map { .init(index: $0.offset, item: $0.element) }
        guard !removal.history.isEmpty else { return removal }
        let ids = Set(removal.history.map(\.item.id))
        clipboardHistory.removeAll { ids.contains($0.id) }
        holdPictures(of: &removal)
        saveHistoryToDefaults()
        rescheduleExpiry()
        return removal
    }

    /// Puts removed entries back at their places. An entry whose content was
    /// copied again in the meantime is not doubled: its leftovers go.
    func restore(_ removal: Removal) {
        var dropped: [ClipboardItem] = []
        for (id, data) in removal.pictures { ClipboardItem.storeInMemoryImage(data, for: id) }
        for entry in removal.pinned.sorted(by: { $0.index < $1.index }) {
            guard !pinnedItems.contains(where: { $0.id == entry.item.id }) else { continue }
            pinnedItems.insert(entry.item, at: min(entry.index, pinnedItems.count))
        }
        for entry in removal.history.sorted(by: { $0.index < $1.index }) {
            if clipboardHistory.contains(where: { $0.id == entry.item.id || $0.isSameContent(as: entry.item) }) {
                dropped.append(entry.item)
                continue
            }
            clipboardHistory.insert(entry.item, at: min(entry.index, clipboardHistory.count))
        }
        if clipboardHistory.count > maxHistoryItems {
            dropped += clipboardHistory.dropFirst(maxHistoryItems)
            clipboardHistory = Array(clipboardHistory.prefix(maxHistoryItems))
        }
        deleteUnreferencedFiles(of: dropped)
        saveHistoryToDefaults()
        if !removal.pinned.isEmpty { savePinnedItemsToDefaults() }
        rescheduleExpiry()
    }

    /// «Отменить» is over: the removed entries' picture files go.
    func finishRemoval(_ removal: Removal) {
        deleteUnreferencedFiles(of: removal.items)
    }

    /// Pictures that live only in memory are pruned as soon as their entry
    /// leaves the lists; the removal holds them until it is undone or over.
    private func holdPictures(of removal: inout Removal) {
        for item in removal.items where item.type == .image && item.imageFileName == nil {
            if let data = ClipboardItem.inMemoryImage(for: item.id) { removal.pictures[item.id] = data }
        }
    }

    private func deleteUnreferencedFiles(of items: [ClipboardItem]) {
        let referenced = Set(clipboardHistory.compactMap(\.imageFileName)).union(pinnedItems.compactMap(\.imageFileName))
        for item in items {
            guard let fileName = item.imageFileName, !referenced.contains(fileName) else { continue }
            try? FileManager.default.removeItem(at: ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName))
        }
    }

    /// Clears favorites, deleting the image files behind them.
    ///
    /// Callers used to empty `pinnedItems` and save directly, which left the
    /// PNG of every pinned image orphaned in `clipboardDataDirectory` forever —
    /// `clearHistory()` deletes files, this path did not.
    func clearPinnedItems() {
        for item in pinnedItems {
            guard let fileName = item.imageFileName else { continue }
            let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }

        pinnedItems.removeAll()
        savePinnedItemsToDefaults()
        ClipboardItem.pruneInMemoryImages(
            keeping: Set(clipboardHistory.map { $0.id })
        )
    }

    func pinItem(_ item: ClipboardItem) {
        // Update the item to be pinned
        var pinnedItem = item
        pinnedItem.isPinned = true
        
        // Remove from regular history if it exists there
        clipboardHistory.removeAll { $0.id == item.id }
        
        // Add to pinned items if not already there
        if !pinnedItems.contains(where: { $0.id == item.id }) {
            // While history is not being saved an image lives only in memory,
            // with no file behind it -- but the pinned record about to be
            // written names a file, and a restart would restore a pinned
            // entry with no picture in it. With "Save pinned items" on,
            // pinning is a request to keep this one thing, so this one image
            // gets a file; otherwise pinned items stay in memory too.
            if Defaults[.clipboardPersistPinned], pinnedItem.type == .image, pinnedItem.imageFileName == nil {
                pinnedItem.imageFileName = persistImageFile(for: pinnedItem.id)
            }
            pinnedItems.append(pinnedItem)
        }
        
        saveHistoryToDefaults()
        savePinnedItemsToDefaults()
    }

    /// Writes an in-memory image out and returns the file's name, or nil when
    /// there are no bytes held for the item or the write fails.
    private func persistImageFile(for id: UUID) -> String? {
        guard let data = ClipboardItem.inMemoryImage(for: id) else { return nil }
        let name = "clipboard_image_\(UUID().uuidString).png"
        let url = ClipboardManager.clipboardDataDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return name
        } catch {
            print("Failed to persist clipboard image: \(error)")
            return nil
        }
    }
    
    func unpinItem(_ item: ClipboardItem) {
        // Remove from pinned items
        pinnedItems.removeAll { $0.id == item.id }
        
        // Update the item to be unpinned and add back to regular history
        var unpinnedItem = item
        unpinnedItem.isPinned = false
        
        // Add back to regular history at the top
        clipboardHistory.insert(unpinnedItem, at: 0)
        
        // Maintain history size limit
        if clipboardHistory.count > maxHistoryItems {
            let itemsToDelete = Array(clipboardHistory.dropFirst(maxHistoryItems))
            for oldItem in itemsToDelete {
                if let fileName = oldItem.imageFileName {
                    let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            clipboardHistory = Array(clipboardHistory.prefix(maxHistoryItems))
        }
        
        saveHistoryToDefaults()
        savePinnedItemsToDefaults()
    }
    
    func togglePin(for item: ClipboardItem) {
        if item.isPinned || pinnedItems.contains(where: { $0.id == item.id }) {
            unpinItem(item)
        } else {
            pinItem(item)
        }
    }
    
    // MARK: - Private Methods
    
    private func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // Looked at once a second, so the frontmost app is the one the copy
        // was made in.
        captureChange(
            from: .general,
            sourceBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }

    /// Adds the pasteboard's content to the history unless the capture policy
    /// refuses it (paused, concealed/transient markers, ignored source app).
    /// Takes the pasteboard as a parameter so tests can use a private one
    /// instead of the user's clipboard.
    @discardableResult
    func captureChange(from pasteboard: NSPasteboard, sourceBundleID: String?) -> ClipboardCapturePolicy.Decision {
        if ClipboardOwnWrites.isOwnWrite(pasteboard) { return .ownWrite }
        let decision = ClipboardCapturePolicy.decide(
            types: ClipboardCapturePolicy.allTypes(on: pasteboard),
            sourceBundleID: sourceBundleID,
            isPaused: Defaults[.clipboardHistoryPaused],
            ignoredApps: Defaults[.clipboardIgnoredApps]
        )
        guard decision == .record else { return decision }
        if ClipboardScreenshotDetector.routesToScreenshots, ClipboardScreenshotDetector.isScreenshot(pasteboard) {
            ClipboardShotLog.note("history: change \(pasteboard.changeCount) routed to screenshots")
            return .routedToScreenshots
        }

        guard var clipboardItem = getCurrentClipboardItem(from: pasteboard) else { return decision }
        clipboardItem.sourceBundleID = sourceBundleID
        
        // Copying something that is already in the history moves it to the
        // top: `addToHistory` drops the older entry and its picture file.
        // (Skipping the copy left it where it was and orphaned the picture
        // file the new entry had already written.)
        addToHistory(clipboardItem)
        // A picture may be the first of a run of screenshots: look fast for
        // a few seconds so the next ones are not replaced unseen.
        if clipboardItem.type == .image, pasteboard === NSPasteboard.general {
            ClipboardChangeWatcher.shared.burst()
        }
        return decision
    }
    
    private func getCurrentClipboardItem(from pasteboard: NSPasteboard) -> ClipboardItem? {
        
        // Step 1: Check what types are available
        let hasFileURLs = pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
        let hasImageData = pasteboard.data(forType: .png) != nil || 
                          pasteboard.data(forType: .tiff) != nil || 
                          pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) != nil
        let hasString = pasteboard.string(forType: .string) != nil
        
        // Step 2: Smart detection based on context
        
        // Priority 1: If there are file URLs AND the files are actual image files, treat as image files (from Finder)
        if hasFileURLs {
            if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                let realFileURLs = fileURLs.filter { url in
                    return url.isFileURL && 
                           !url.path.contains("/.file/id=") && 
                           !url.path.contains("/tmp/") && 
                           !url.path.hasPrefix("/private/var/") && 
                           !url.path.contains("/ClipboardViewer") && 
                           FileManager.default.fileExists(atPath: url.path)
                }
                
                if !realFileURLs.isEmpty {
                    // Check if these are image files - if so, try to load the actual image data
                    let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]
                    let imageFiles = realFileURLs.filter { url in
                        imageExtensions.contains(url.pathExtension.lowercased())
                    }
                    
                    // One picture from Finder: keep the picture itself. Several
                    // files (pictures or not) stay files, so none is lost.
                    if ClipboardFinderCopy.keepsAsPicture(fileCount: realFileURLs.count, imageCount: imageFiles.count),
                       let imageData = try? Data(contentsOf: imageFiles[0]) {
                        return ClipboardItem(imageData: imageData)
                    }
                    
                    // Otherwise, treat as file(s)
                    let urlStrings = realFileURLs.map { $0.absoluteString }
                    return ClipboardItem(fileURLs: urlStrings)
                }
            }
        }
        
        // Priority 2: If there's ONLY image data without file URLs (screenshots, direct image paste)
        if hasImageData && !hasFileURLs {
            if let imageData = pasteboard.data(forType: .png) {
                return ClipboardItem(imageData: imageData)
            } else if let imageData = pasteboard.data(forType: .tiff) {
                return ClipboardItem(imageData: imageData)
            } else if let imageData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
                return ClipboardItem(imageData: imageData)
            }
        }
        
        // Resolve any rich representation up front so the URL branch below can defer to it:
        // a formatted URL selection (e.g. a link copied from a rich-text editor or web page)
        // exposes an `https://` string *and* RTF/HTML, and must not be flattened to a bare URL.
        let richText = pasteboard.rtfDataWithFallback()

        // Priority 3: Plain-text URLs stay typed as `.url` (address-bar copies carry no RTF).
        // Only when there is no usable rich representation — otherwise the formatting wins.
        if let string = pasteboard.string(forType: .string), !string.isEmpty,
           richText == nil,
           string.hasPrefix("http://") || string.hasPrefix("https://") {
            return ClipboardItem(stringData: string, type: .url)
        }

        // Priority 4: Rich text. Must come before plain text: any rich copy also exposes a
        // `.string` representation, so checking plain text first would shadow rich content and
        // the item would lose its formatting at capture time. Capturing here keeps styled
        // `rtfData` with a plain-text fallback, so both drag-out and copy-back preserve
        // formatting. Prefer real RTF; otherwise synthesize it from HTML — browsers (GitHub,
        // web pages) put `public.html` on the pasteboard but no `public.rtf`, so without this
        // step the common "copy from a web page" case would still drop as plain text.
        if let richText {
            return ClipboardItem(rtfData: richText.rtf, plainText: richText.plain)
        }

        // Priority 5: Plain text
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return ClipboardItem(stringData: string, type: .text)
        }

        // Priority 6: If we have image data WITH file URLs (document thumbnails),
        // this is likely a document with a preview - ignore the thumbnail and treat as unknown
        if hasImageData && hasFileURLs {
            // This is likely a document with a thumbnail preview - we don't want the thumbnail
            return nil
        }

        // Priority 7: URL strings
        if let url = pasteboard.string(forType: .URL) {
            return ClipboardItem(stringData: url, type: .url)
        }
        
        return nil
    }
    
    private func addToHistory(_ item: ClipboardItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Remove any existing items with the same data
            let itemsToRemove = self.clipboardHistory.filter { existingItem in
                return self.isSameContent(existingItem, item)
            }
            
            // Clean up files for items being removed
            for oldItem in itemsToRemove {
                if let fileName = oldItem.imageFileName {
                    let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            
            // By identity: comparing content again after the files are gone
            // found pictures different and kept the old entry, now without
            // its picture.
            let removedIDs = Set(itemsToRemove.map(\.id))
            self.clipboardHistory.removeAll { removedIDs.contains($0.id) }
            
            // Add to beginning of array
            self.clipboardHistory.insert(item, at: 0)
            self.lastCopiedItemDate = item.timestamp
            // A code goes after two minutes; the first entry of an empty
            // history also starts the age-based clock.
            self.rescheduleExpiry()
            
            // Keep only the most recent items and clean up old files
            let itemsToDelete = Array(self.clipboardHistory.dropFirst(self.maxHistoryItems))
            for oldItem in itemsToDelete {
                if let fileName = oldItem.imageFileName {
                    let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            
            if self.clipboardHistory.count > self.maxHistoryItems {
                self.clipboardHistory = Array(self.clipboardHistory.prefix(self.maxHistoryItems))
            }
            
            self.saveHistoryToDefaults()
        }
    }
    
    // Helper to compare clipboard items for duplicates
    private func isSameContent(_ item1: ClipboardItem, _ item2: ClipboardItem) -> Bool {
        if item1.type != item2.type { return false }
        
        switch item1.type {
        case .text, .url, .unknown:
            return item1.stringData == item2.stringData
        case .image:
            // For images, compare the actual data if both are available
            let data1 = item1.getImageData()
            let data2 = item2.getImageData()
            return data1 == data2
        case .file:
            return item1.fileURLs == item2.fileURLs
        case .rtf:
            return item1.stringData == item2.stringData && item1.rtfData == item2.rtfData
        }
    }
    
    // Clean up old image files that are no longer referenced
    private func cleanupOldFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: ClipboardManager.clipboardDataDirectory, includingPropertiesForKeys: nil) else { return }
        
        // Pinned items live in the same directory; leaving them out here
        // deleted the image behind every favorite on the next launch.
        let referencedFiles = Set(clipboardHistory.compactMap { $0.imageFileName })
            .union(pinnedItems.compactMap { $0.imageFileName })
        
        for file in files {
            let fileName = file.lastPathComponent
            if !referencedFiles.contains(fileName) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveHistoryToDefaults() {
        // Runs on every history mutation, so it is the natural place to drop
        // image bytes for items that are no longer around.
        ClipboardItem.pruneInMemoryImages(
            keeping: Set(clipboardHistory.map { $0.id }).union(pinnedItems.map { $0.id })
        )

        guard Defaults[.persistClipboardHistory] else {
            // Keep the session's history in memory, but leave nothing behind.
            ClipboardManager.removeStoredHistory()
            return
        }

        if let encoded = try? JSONEncoder().encode(clipboardHistory) {
            UserDefaults.standard.set(encoded, forKey: "ClipboardHistory")
        }
    }
    
    func savePinnedItemsToDefaults() {
        guard Defaults[.clipboardPersistPinned] else {
            UserDefaults.standard.removeObject(forKey: "ClipboardPinnedItems")
            return
        }
        if let encoded = try? JSONEncoder().encode(pinnedItems) {
            UserDefaults.standard.set(encoded, forKey: "ClipboardPinnedItems")
        }
    }
    
    private func loadHistoryFromDefaults() {
        if Defaults[.persistClipboardHistory] {
            if let data = UserDefaults.standard.data(forKey: "ClipboardHistory"),
               let history = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
                clipboardHistory = history
            }
        } else {
            // Covers history stored before the setting was turned off, and any
            // written by an older build that did not know about it.
            ClipboardManager.removeStoredHistory()
        }
        
        guard Defaults[.clipboardPersistPinned] else {
            UserDefaults.standard.removeObject(forKey: "ClipboardPinnedItems")
            return
        }
        if let data = UserDefaults.standard.data(forKey: "ClipboardPinnedItems"),
           let pinned = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            pinnedItems = pinned
        }
    }
}

private extension NSPasteboard {
    /// Extract rich text as RTF data plus a plain-text fallback, or `nil` when the pasteboard
    /// holds no rich content. Prefers a real `public.rtf` representation; when only HTML is
    /// present — browsers and sites like GitHub expose `public.html` but no `public.rtf` — the
    /// HTML is parsed into an attributed string and re-encoded as RTF so the formatting is
    /// captured instead of lost. Must be called on the main thread: HTML import spins up WebKit.
    func rtfDataWithFallback() -> (rtf: Data, plain: String)? {
        if let rtfData = data(forType: .rtf),
           let string = NSAttributedString(rtf: rtfData, documentAttributes: nil)?.string,
           !string.isEmpty {
            return (rtfData, string)
        }
        if let htmlData = data(forType: .html),
           let attributed = try? NSAttributedString(
               data: htmlData,
               options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil),
           !attributed.string.isEmpty,
           let rtf = try? attributed.data(
               from: NSRange(location: 0, length: attributed.length),
               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            return (rtf, attributed.string)
        }
        return nil
    }
}

/// What a copy of files in Finder becomes in the history.
enum ClipboardFinderCopy {
    /// One picture file is kept as the picture; several files are kept as
    /// files (upstream kept only the first of several pictures).
    static func keepsAsPicture(fileCount: Int, imageCount: Int) -> Bool {
        fileCount == 1 && imageCount == 1
    }
}
