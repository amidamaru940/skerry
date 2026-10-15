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

@testable import Atoll
import AppKit
import Defaults
import XCTest

// MARK: - Batches

final class ScreenshotBatchStoreTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var existing: Set<String> = []

    private func makeStore(gapMinutes: Double = 15, fileURL: URL? = nil) -> ScreenshotBatchStore {
        ScreenshotBatchStore(fileURL: fileURL, batchGap: { gapMinutes * 60 }, fileExists: { [unowned self] in self.existing.contains($0) })
    }

    private func shot(_ name: String) -> URL {
        let url = URL(fileURLWithPath: "/tmp/shots/\(name).png")
        existing.insert(url.path)
        return url
    }

    func testScreenshotsInARowShareABatch() {
        let store = makeStore()
        store.add(shot("a"), capturedAt: start)
        store.add(shot("b"), capturedAt: start.addingTimeInterval(60))
        store.add(shot("c"), capturedAt: start.addingTimeInterval(14 * 60 + 60))

        XCTAssertEqual(store.batches.count, 1)
        XCTAssertEqual(store.currentBatch?.items.map(\.url.lastPathComponent), ["a.png", "b.png", "c.png"])
        XCTAssertEqual(store.currentBatch?.newestFirst.map(\.url.lastPathComponent), ["c.png", "b.png", "a.png"])
    }

    func testALongPauseStartsANewBatch() {
        let store = makeStore(gapMinutes: 15)
        store.add(shot("a"), capturedAt: start)
        store.add(shot("b"), capturedAt: start.addingTimeInterval(15 * 60 + 1))

        XCTAssertEqual(store.batches.count, 2)
        XCTAssertEqual(store.currentBatch?.items.map(\.url.lastPathComponent), ["b.png"])
    }

    func testGapIsMeasuredFromTheLastScreenshot() {
        let store = makeStore(gapMinutes: 15)
        for minute in stride(from: 0, through: 40, by: 10) {
            store.add(shot("m\(minute)"), capturedAt: start.addingTimeInterval(Double(minute) * 60))
        }
        XCTAssertEqual(store.batches.count, 1, "10-minute steps stay within a 15-minute gap")
    }

    func testDuplicatePathIsIgnored() {
        let store = makeStore()
        XCTAssertTrue(store.add(shot("a"), capturedAt: start))
        XCTAssertFalse(store.add(shot("a"), capturedAt: start.addingTimeInterval(5)))
        XCTAssertEqual(store.allItems.count, 1)
    }

    func testClearingTheCurrentBatchStartsANewOne() {
        let store = makeStore()
        store.add(shot("a"), capturedAt: start)
        store.add(shot("b"), capturedAt: start.addingTimeInterval(30))
        let cleared = store.clear(batchID: store.currentBatch!.id)
        store.add(shot("c"), capturedAt: start.addingTimeInterval(60))

        XCTAssertEqual(cleared.map(\.url.lastPathComponent), ["a.png", "b.png"])
        XCTAssertEqual(store.batches.count, 1)
        XCTAssertEqual(store.currentBatch?.items.map(\.url.lastPathComponent), ["c.png"])
    }

    func testKeepSelectedRemovesOnlyTheOthersInThatBatch() {
        let store = makeStore()
        store.add(shot("old"), capturedAt: start)
        let a = shot("a"), b = shot("b"), c = shot("c")
        store.add(a, capturedAt: start.addingTimeInterval(3600))
        store.add(b, capturedAt: start.addingTimeInterval(3610))
        store.add(c, capturedAt: start.addingTimeInterval(3620))

        let removed = store.keepOnly([a.path, c.path])

        XCTAssertEqual(removed.map(\.url.lastPathComponent), ["b.png"])
        XCTAssertEqual(store.currentBatch?.items.map(\.url.lastPathComponent), ["a.png", "c.png"])
        XCTAssertEqual(store.batches.count, 2, "the older batch had no selection and is untouched")
    }

    func testRemoveTakesScreenshotsOutOfTheirBatches() {
        let store = makeStore()
        let a = shot("a"), b = shot("b")
        store.add(a, capturedAt: start)
        store.add(b, capturedAt: start.addingTimeInterval(10))

        store.remove([a.path])
        XCTAssertEqual(store.allItems.map(\.url.lastPathComponent), ["b.png"])
        store.remove([b.path])
        XCTAssertTrue(store.isEmpty, "an emptied batch disappears")
    }

    func testMissingFilesDisappear() {
        let store = makeStore()
        let a = shot("a"), b = shot("b")
        store.add(a, capturedAt: start)
        store.add(b, capturedAt: start.addingTimeInterval(10))

        existing.remove(a.path)
        store.pruneMissingFiles()

        XCTAssertEqual(store.allItems.map(\.url.lastPathComponent), ["b.png"])
    }

    func testBatchesSurviveARestartAsPathsOnly() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("amg-batches-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let a = shot("a"), b = shot("b")

        let first = makeStore(fileURL: file)
        first.add(a, capturedAt: start)
        first.add(b, capturedAt: start.addingTimeInterval(10))

        existing.remove(b.path)
        let reopened = makeStore(fileURL: file)
        XCTAssertEqual(reopened.allItems.map(\.url.lastPathComponent), ["a.png"], "a file gone since the restart is dropped")

        let json = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(json.contains("\"path\""))
        XCTAssertFalse(json.contains("PNG"), "only paths and dates are stored, no image data")
    }

    func testDragURLsAreInCaptureOrder() {
        let store = makeStore()
        let shots = (0..<4).map { shot("s\($0)") }
        for (index, url) in shots.enumerated() {
            store.add(url, capturedAt: start.addingTimeInterval(Double(index) * 20))
        }

        let selected: Set<String> = [shots[3].path, shots[0].path, shots[2].path]
        let urls = store.fileURLs(for: selected)

        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["s0.png", "s2.png", "s3.png"])
        XCTAssertTrue(urls.allSatisfy(\.isFileURL))
    }

    func testDragURLsSpanBatchesOldestFirst() {
        let store = makeStore(gapMinutes: 1)
        let early = shot("early"), late = shot("late")
        store.add(early, capturedAt: start)
        store.add(late, capturedAt: start.addingTimeInterval(3600))

        XCTAssertEqual(store.fileURLs(for: [late.path, early.path]).map(\.lastPathComponent), ["early.png", "late.png"])
    }

    func testScreenshotDefaults() {
        XCTAssertFalse(Defaults.Keys.screenshotMoveOriginalsToTrash.defaultValue)
        XCTAssertFalse(Defaults.Keys.collectClipboardScreenshots.defaultValue)
        XCTAssertTrue(Defaults.Keys.enableScreenshotShelf.defaultValue)
        XCTAssertEqual(Defaults.Keys.screenshotBatchGapMinutes.defaultValue, 15)
    }
}

// MARK: - Location

final class ScreenshotLocationTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    func testDefaultsToDesktop() {
        XCTAssertEqual(ScreenshotLocation.resolve(rawLocation: nil, home: home).path, "/Users/someone/Desktop")
        XCTAssertEqual(ScreenshotLocation.resolve(rawLocation: "  ", home: home).path, "/Users/someone/Desktop")
    }

    func testExpandsTildeAndKeepsSpaces() {
        XCTAssertEqual(ScreenshotLocation.resolve(rawLocation: "~/Screenshots", home: home).path, "/Users/someone/Screenshots")
        XCTAssertEqual(ScreenshotLocation.resolve(rawLocation: "~/My Shots/", home: home).path, "/Users/someone/My Shots")
        XCTAssertEqual(ScreenshotLocation.resolve(rawLocation: "/Volumes/Data/Скриншоты", home: home).path, "/Volumes/Data/Скриншоты")
        XCTAssertEqual(ScreenshotLocation.resolve(rawLocation: "file:///Users/someone/Pictures/Shots%20Here/", home: home).path,
                       "/Users/someone/Pictures/Shots Here")
    }

    func testFlagsDesktopAndDocuments() {
        XCTAssertTrue(ScreenshotLocation.isDesktopOrDocuments(home.appendingPathComponent("Desktop"), home: home))
        XCTAssertTrue(ScreenshotLocation.isDesktopOrDocuments(home.appendingPathComponent("Documents/Shots"), home: home))
        XCTAssertFalse(ScreenshotLocation.isDesktopOrDocuments(home.appendingPathComponent("Screenshots"), home: home))
        XCTAssertFalse(ScreenshotLocation.isDesktopOrDocuments(home.appendingPathComponent("DesktopArchive"), home: home))
    }
}

// MARK: - Detection

final class ScreenshotWatcherTests: XCTestCase {
    private var folder: URL!
    private var found: [URL] = []
    private var watcher: ScreenshotWatcher?

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-shots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        found = []
    }

    override func tearDownWithError() throws {
        watcher?.stop()
        watcher = nil
        try? FileManager.default.removeItem(at: folder)
    }

    private func startWatching() {
        let watcher = ScreenshotWatcher(folder: folder, startDate: Date(), useSpotlight: false) { [weak self] url, _ in
            self?.found.append(url)
        }
        watcher.start()
        self.watcher = watcher
    }

    /// The marker macOS puts on screenshots.
    private func markAsScreenCapture(_ url: URL) throws {
        let value = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = value.withUnsafeBytes {
            setxattr(url.path, ScreenshotWatcher.screenCaptureAttribute, $0.baseAddress, value.count, 0, 0)
        }
        XCTAssertEqual(result, 0)
    }

    private func pump(_ seconds: TimeInterval = 1.5) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// macOS writes ".Screenshot …png" and renames it; exactly one add, for the final name.
    func testRenamedScreenshotIsReportedOnce() throws {
        startWatching()
        let temp = folder.appendingPathComponent(".Снимок экрана 2026-10-14 в 21.00.00.png")
        let final = folder.appendingPathComponent("Снимок экрана 2026-10-14 в 21.00.00.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: temp)
        try markAsScreenCapture(temp)
        pump(0.3)
        try FileManager.default.moveItem(at: temp, to: final)
        pump()

        XCTAssertEqual(found.map(\.lastPathComponent), [final.lastPathComponent])

        // A later change to the same file must not add it again.
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D]).write(to: final)
        try markAsScreenCapture(final)
        pump()
        XCTAssertEqual(found.count, 1)
    }

    func testNonScreenshotsAreIgnored() throws {
        startWatching()
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("photo.png"))      // image, no marker
        try Data("notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        let recording = folder.appendingPathComponent("Запись экрана.mov")            // screen recording
        try Data([0]).write(to: recording)
        try markAsScreenCapture(recording)
        pump()

        XCTAssertEqual(found, [])
    }

    func testScreenshotsFromBeforeLaunchAreIgnored() throws {
        let old = folder.appendingPathComponent("Screenshot old.png")
        try Data([1]).write(to: old)
        try markAsScreenCapture(old)
        startWatching()
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: old.path)
        pump()

        XCTAssertEqual(found, [])
    }
}

// MARK: - Selection, drag and removal

@MainActor
final class ScreenshotShelfManagerTests: XCTestCase {
    private var folder: URL!
    private var manager: ScreenshotShelfManager!
    private var savedTrash = false
    private let start = Date()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        savedTrash = Defaults[.screenshotMoveOriginalsToTrash]
        Defaults[.screenshotMoveOriginalsToTrash] = false
        manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 15 * 60 }))
    }

    override func tearDownWithError() throws {
        Defaults[.screenshotMoveOriginalsToTrash] = savedTrash
        try? FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    private func capture(_ count: Int) throws -> [ScreenshotItem] {
        for index in 0..<count {
            let url = folder.appendingPathComponent("shot-\(index).png")
            try Data([UInt8(index)]).write(to: url)
            manager.didCapture(url, at: start.addingTimeInterval(Double(index)))
        }
        return manager.store.currentBatch!.items
    }

    /// Owner's choice (15.10): every click adds or removes, like ticks.
    func testEveryClickAddsOrRemovesLikeTicks() throws {
        let items = try capture(3)
        manager.click(items[0], extend: false)
        XCTAssertEqual(manager.selection, [items[0].id])
        manager.click(items[2], extend: true)
        XCTAssertEqual(manager.selection, [items[0].id, items[2].id])
        manager.click(items[2], extend: true)
        XCTAssertEqual(manager.selection, [items[0].id], "Cmd-click again removes it")
        manager.click(items[1], extend: false)
        XCTAssertEqual(manager.selection, [items[0].id, items[1].id], "a plain click adds the second one too")
        manager.click(items[1], extend: false)
        XCTAssertEqual(manager.selection, [items[0].id], "clicking a chosen one removes it")
        manager.click(items[0], extend: false)
        XCTAssertEqual(manager.selection, [], "and the last one")
    }

    func testSelectAllOfABatchAndDeselect() throws {
        let items = try capture(3)
        let batch = try XCTUnwrap(manager.store.currentBatch)
        manager.click(items[1], extend: false)
        XCTAssertFalse(manager.isFullySelected(batch))
        manager.toggleSelectAll(in: batch)
        XCTAssertEqual(manager.selection, Set(items.map(\.id)))
        XCTAssertTrue(manager.isFullySelected(batch))
        manager.toggleSelectAll(in: batch)
        XCTAssertEqual(manager.selection, [])
    }

    func testSelectAllAndDragCarriesEverySelectedFileInCaptureOrder() throws {
        let items = try capture(4)
        manager.selectAll()
        XCTAssertEqual(manager.selection.count, 4)

        manager.click(items[1], extend: true)  // deselect one
        let urls = manager.dragURLs(startingAt: items[3])

        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["shot-0.png", "shot-2.png", "shot-3.png"])
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testDraggingAnUnselectedTileCarriesOnlyIt() throws {
        let items = try capture(3)
        manager.click(items[0], extend: false)
        XCTAssertEqual(manager.dragURLs(startingAt: items[2]).map(\.lastPathComponent), ["shot-2.png"])
    }

    func testRemoveKeepAndClearLeaveTheOriginals() throws {
        let items = try capture(4)
        manager.click(items[0], extend: false)
        manager.removeSelected()
        manager.click(items[1], extend: false)
        manager.click(items[2], extend: true)
        manager.keepSelected()

        XCTAssertEqual(manager.store.allItems.map(\.url.lastPathComponent), ["shot-1.png", "shot-2.png"])
        manager.clear(batchID: manager.store.currentBatch!.id)
        XCTAssertTrue(manager.store.isEmpty)
        XCTAssertEqual(manager.selection, [])
        for item in items {
            XCTAssertTrue(FileManager.default.fileExists(atPath: item.path), "\(item.url.lastPathComponent) was deleted")
        }
    }

    func testANewScreenshotFlashesWithTheBatchCount() throws {
        try capture(2)
        XCTAssertEqual(manager.flash?.count, 2)
        XCTAssertEqual(manager.flash?.url.lastPathComponent, "shot-1.png")
    }
}

// MARK: - Clipboard screenshots

final class ClipboardScreenshotCollectorTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var folder: URL!
    private var savedToolCheck: (() -> Bool)!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.amidamaru940.skerry.tests.\(UUID().uuidString)"))
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-clip-\(UUID().uuidString)", isDirectory: true)
        // As if ⌃⇧⌘4 was just used: the screenshot tool is running.
        savedToolCheck = ClipboardScreenshotDetector.isScreenshotToolRunning
        ClipboardScreenshotDetector.isScreenshotToolRunning = { true }
    }

    override func tearDown() {
        ClipboardScreenshotDetector.isScreenshotToolRunning = savedToolCheck
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testAPictureAloneCountsAsAScreenshot() throws {
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(png(), forType: .png)

        let saved = try XCTUnwrap(ClipboardScreenshotCollector.saveIfScreenshot(from: pasteboard, sourceBundleID: "com.apple.finder", to: folder))
        XCTAssertEqual(saved.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
    }

    func testAPictureWithTextOrFileIsNotAScreenshot() {
        pasteboard.declareTypes([.png, .string], owner: nil)
        pasteboard.setData(png(), forType: .png)
        pasteboard.setString("caption", forType: .string)
        XCTAssertNil(ClipboardScreenshotCollector.screenshotImageData(from: pasteboard))

        pasteboard.clearContents()
        pasteboard.setString("just text", forType: .string)
        XCTAssertNil(ClipboardScreenshotCollector.screenshotImageData(from: pasteboard))
    }

    func testAPictureCopiedWithoutTheScreenshotToolIsNotSaved() {
        ClipboardScreenshotDetector.isScreenshotToolRunning = { false }
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(png(), forType: .png)

        XCTAssertNil(ClipboardScreenshotCollector.saveIfScreenshot(from: pasteboard, sourceBundleID: "com.apple.Preview", to: folder))
    }

    func testABurstOfClipboardScreenshotsIsAllCollected() {
        // ⌃⇧⌘3 pressed quickly: each shot replaces the clipboard picture.
        // Every change is taken when it is seen; writing happens off the
        // main thread, so a slow write no longer delays the next look.
        XCTAssertLessThanOrEqual(ClipboardScreenshotCollector.pollInterval, 0.1)
        var saved: [URL] = []
        let written = expectation(description: "every shot written")
        written.expectedFulfillmentCount = 4
        let collector = ClipboardScreenshotCollector(pasteboard: pasteboard, folder: folder) { url, _ in
            saved.append(url)
            written.fulfill()
        }
        for _ in 0..<4 {
            pasteboard.declareTypes([.png], owner: nil)
            pasteboard.setData(png(), forType: .png)
            collector.poll()
        }
        collector.poll() // nothing new: nothing more
        wait(for: [written], timeout: 5)
        XCTAssertEqual(Set(saved).count, 4, "four shots, four files")
        XCTAssertTrue(saved.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testConcealedPicturesAreNotSaved() {
        pasteboard.declareTypes([.png, .init("org.nspasteboard.ConcealedType")], owner: nil)
        pasteboard.setData(png(), forType: .png)
        pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))

        XCTAssertNil(ClipboardScreenshotCollector.saveIfScreenshot(from: pasteboard, sourceBundleID: "com.apple.finder", to: folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}

// MARK: - Setup helper

final class ScreenshotSystemSettingsTests: XCTestCase {
    private var recorded: [ScreenshotSystemSettings.Command] = []
    private var savedRunner: ((ScreenshotSystemSettings.Command) -> Int32)!
    private var savedPrevious: String?

    override func setUp() {
        super.setUp()
        savedRunner = ScreenshotSystemSettings.runner
        savedPrevious = Defaults[.screenshotThumbnailPreviousValue]
        // Never touch the real screenshot settings from tests.
        ScreenshotSystemSettings.runner = { [unowned self] command in
            self.recorded.append(command)
            return 0
        }
    }

    override func tearDown() {
        ScreenshotSystemSettings.runner = savedRunner
        Defaults[.screenshotThumbnailPreviousValue] = savedPrevious
        super.tearDown()
    }

    func testUseFolderCreatesItAndWritesTheLocation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg Screenshots \(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertTrue(ScreenshotSystemSettings.useFolder(folder))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(recorded, [
            .init(executable: "/usr/bin/defaults", arguments: ["write", "com.apple.screencapture", "location", folder.path]),
            .init(executable: "/usr/bin/killall", arguments: ["SystemUIServer"]),
        ])
    }

    func testHidingTheThumbnailCanBeUndone() {
        Defaults[.screenshotThumbnailPreviousValue] = nil
        ScreenshotSystemSettings.hideFloatingThumbnail()
        let previous = Defaults[.screenshotThumbnailPreviousValue]
        XCTAssertNotNil(previous)
        XCTAssertEqual(recorded.first?.arguments, ["write", "com.apple.screencapture", "show-thumbnail", "-bool", "false"])

        recorded = []
        ScreenshotSystemSettings.undoHideFloatingThumbnail()
        let restore = previous == "unset"
            ? ["delete", "com.apple.screencapture", "show-thumbnail"]
            : ["write", "com.apple.screencapture", "show-thumbnail", "-bool", previous!]
        XCTAssertEqual(recorded.first?.arguments, restore)
        XCTAssertNil(Defaults[.screenshotThumbnailPreviousValue])
    }

    func testUndoRestoresAnUnsetValueByDeletingIt() {
        XCTAssertEqual(ScreenshotSystemSettings.undoHideThumbnailCommands(previous: "unset").first?.arguments,
                       ["delete", "com.apple.screencapture", "show-thumbnail"])
        XCTAssertEqual(ScreenshotSystemSettings.undoHideThumbnailCommands(previous: "true").first?.arguments,
                       ["write", "com.apple.screencapture", "show-thumbnail", "-bool", "true"])
    }
}
