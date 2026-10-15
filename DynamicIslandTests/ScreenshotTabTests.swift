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

private func testPNG() -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Recognising clipboard screenshots

final class ClipboardScreenshotDetectorTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var savedToolCheck: (() -> Bool)!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.amidamaru940.skerry.tests.\(UUID().uuidString)"))
        savedToolCheck = ClipboardScreenshotDetector.isScreenshotToolRunning
    }

    override func tearDown() {
        ClipboardScreenshotDetector.isScreenshotToolRunning = savedToolCheck
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    /// What a ⌃⇧⌘4 screenshot put on the clipboard on macOS 26.6.
    private func putScreenshotLikeContent() {
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(testPNG(), forType: .png)
    }

    func testPictureWhileTheScreenshotToolRunsIsAScreenshot() {
        ClipboardScreenshotDetector.isScreenshotToolRunning = { true }
        putScreenshotLikeContent()
        XCTAssertTrue(ClipboardScreenshotDetector.isScreenshot(pasteboard))
    }

    func testTheSamePictureWithoutTheToolIsAnOrdinaryPicture() {
        ClipboardScreenshotDetector.isScreenshotToolRunning = { false }
        putScreenshotLikeContent()
        XCTAssertFalse(ClipboardScreenshotDetector.isScreenshot(pasteboard))
    }

    func testTextIsNeverAScreenshot() {
        ClipboardScreenshotDetector.isScreenshotToolRunning = { true }
        pasteboard.declareTypes([.png, .string], owner: nil)
        pasteboard.setData(testPNG(), forType: .png)
        pasteboard.setString("caption", forType: .string)
        XCTAssertFalse(ClipboardScreenshotDetector.isScreenshot(pasteboard))
    }

    func testToolNamesAndProcessListing() {
        XCTAssertEqual(ClipboardScreenshotDetector.toolProcessNames, ["screencapture", "screencaptureui"])
        let names = RunningProcesses.names()
        XCTAssertTrue(names.contains(String(ProcessInfo.processInfo.processName.prefix(16))), "the test host itself is listed")
        XCTAssertGreaterThan(names.count, 10)
    }
}

// MARK: - Routing between the clipboard history and the Screenshots tab

@MainActor
final class ClipboardScreenshotRoutingTests: XCTestCase {
    private let clipboard = ClipboardManager.shared
    private var pasteboard: NSPasteboard!
    private var savedToolCheck: (() -> Bool)!
    private var savedHistory: [ClipboardItem] = []
    private var savedCollect = false
    private var savedShelf = true
    private var savedPersist = false
    private var directory: URL!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.amidamaru940.skerry.tests.\(UUID().uuidString)"))
        savedToolCheck = ClipboardScreenshotDetector.isScreenshotToolRunning
        savedHistory = clipboard.clipboardHistory
        savedCollect = Defaults[.collectClipboardScreenshots]
        savedShelf = Defaults[.enableScreenshotShelf]
        savedPersist = Defaults[.persistClipboardHistory]
        Defaults[.persistClipboardHistory] = false
        Defaults[.enableScreenshotShelf] = true
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("amg-routing-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ClipboardManager.directoryOverride = directory
        clipboard.clipboardHistory = []
    }

    override func tearDown() {
        ClipboardScreenshotDetector.isScreenshotToolRunning = savedToolCheck
        clipboard.clipboardHistory = savedHistory
        Defaults[.collectClipboardScreenshots] = savedCollect
        Defaults[.enableScreenshotShelf] = savedShelf
        Defaults[.persistClipboardHistory] = savedPersist
        ClipboardManager.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        pasteboard.releaseGlobally()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        super.tearDown()
    }

    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }

    private func putScreenshot() {
        ClipboardScreenshotDetector.isScreenshotToolRunning = { true }
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(testPNG(), forType: .png)
    }

    func testWithCollectingOnAClipboardScreenshotSkipsTheHistory() {
        Defaults[.collectClipboardScreenshots] = true
        putScreenshot()
        XCTAssertEqual(clipboard.captureChange(from: pasteboard, sourceBundleID: "com.apple.finder"), .routedToScreenshots)
        settle()
        XCTAssertFalse(clipboard.clipboardHistory.contains { $0.type == .image })
    }

    func testWithCollectingOffAClipboardScreenshotIsAnOrdinaryPicture() {
        Defaults[.collectClipboardScreenshots] = false
        putScreenshot()
        XCTAssertEqual(clipboard.captureChange(from: pasteboard, sourceBundleID: "com.apple.finder"), .record)
        settle()
        XCTAssertTrue(clipboard.clipboardHistory.contains { $0.type == .image })
    }

    func testCollectingNeedsScreenshotCollectionOnToo() {
        Defaults[.collectClipboardScreenshots] = true
        Defaults[.enableScreenshotShelf] = false
        XCTAssertFalse(ClipboardScreenshotDetector.routesToScreenshots)
        Defaults[.enableScreenshotShelf] = true
        XCTAssertTrue(ClipboardScreenshotDetector.routesToScreenshots)
    }

    func testTheAppsOwnWritesAreNotRecorded() {
        ClipboardOwnWrites.write(to: pasteboard) { $0.setString("written by Skerry", forType: .string) }
        XCTAssertTrue(ClipboardOwnWrites.isOwnWrite(pasteboard))
        XCTAssertEqual(clipboard.captureChange(from: pasteboard, sourceBundleID: "com.apple.TextEdit"), .ownWrite)
        settle()
        XCTAssertFalse(clipboard.clipboardHistory.contains { $0.stringData == "written by Skerry" })
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1, "the marker adds no extra item")
    }

    func testCopyInTheScreenshotsTabIsNotRecordedInTheClipboardHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))
        let urls = (0..<3).map { folder.appendingPathComponent("shot-\($0).png") }
        for (index, url) in urls.enumerated() {
            try testPNG().write(to: url)
            manager.didCapture(url, at: Date().addingTimeInterval(Double(index)))
        }

        manager.selectAll()
        manager.copySelected(to: pasteboard)
        let copied = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(copied?.map(\.lastPathComponent), ["shot-0.png", "shot-1.png", "shot-2.png"])
        XCTAssertEqual(clipboard.captureChange(from: pasteboard, sourceBundleID: nil), .ownWrite)
        settle()
        XCTAssertTrue(clipboard.clipboardHistory.isEmpty)

        // One screenshot also goes as a picture.
        manager.clearSelection()
        manager.click(manager.store.currentBatch!.items[0], extend: false)
        manager.copySelected(to: pasteboard)
        XCTAssertNotNil(pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first)
        XCTAssertEqual((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.count, 1)
    }
}

// MARK: - Screenshots tab behaviour

@MainActor
final class ScreenshotTabBehaviourTests: XCTestCase {
    private var folder: URL!
    private var manager: ScreenshotShelfManager!
    private var savedRemoveAfterDrag = false
    private var savedTrash = false
    private let start = Date()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-tab-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        savedRemoveAfterDrag = Defaults[.screenshotRemoveAfterDrag]
        savedTrash = Defaults[.screenshotMoveOriginalsToTrash]
        Defaults[.screenshotMoveOriginalsToTrash] = false
        manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))
    }

    override func tearDownWithError() throws {
        Defaults[.screenshotRemoveAfterDrag] = savedRemoveAfterDrag
        Defaults[.screenshotMoveOriginalsToTrash] = savedTrash
        try? FileManager.default.removeItem(at: folder)
    }

    private func capture(_ count: Int) throws {
        for index in 0..<count {
            let url = folder.appendingPathComponent("s\(index).png")
            try Data([UInt8(index)]).write(to: url)
            manager.didCapture(url, at: start.addingTimeInterval(Double(index)))
        }
    }

    func testShiftClickSelectsTheRangeInDisplayOrder() throws {
        try capture(5)                                  // display order: s4 s3 s2 s1 s0
        let order = manager.displayOrder
        XCTAssertEqual(order.map(\.url.lastPathComponent), ["s4.png", "s3.png", "s2.png", "s1.png", "s0.png"])

        manager.click(order[1], extend: false)          // anchor s3
        manager.click(order[3], extend: false, range: true)
        XCTAssertEqual(manager.selection, Set(order[1...3].map(\.id)))

        manager.click(order[0], extend: false, range: true)  // range back up to s4 adds it
        XCTAssertEqual(manager.selection, Set(order[0...3].map(\.id)))
    }

    func testRemoveAfterDragOnlyWhenOnAndTheDropSucceeded() throws {
        try capture(3)
        let dragged = [manager.store.currentBatch!.items[0].url]

        Defaults[.screenshotRemoveAfterDrag] = false
        manager.dragBegan(with: dragged)
        manager.dragEnded(succeeded: true)
        XCTAssertEqual(manager.store.allItems.count, 3, "option off")

        Defaults[.screenshotRemoveAfterDrag] = true
        manager.dragBegan(with: dragged)
        manager.dragEnded(succeeded: false)
        XCTAssertEqual(manager.store.allItems.count, 3, "cancelled drag")

        manager.dragBegan(with: dragged)
        manager.dragEnded(succeeded: true)
        XCTAssertEqual(manager.store.allItems.map(\.url.lastPathComponent), ["s1.png", "s2.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dragged[0].path), "the file itself stays")
        XCTAssertFalse(manager.isDragging)
    }

    func testNewOptionDefaults() {
        XCTAssertFalse(Defaults.Keys.screenshotRemoveAfterDrag.defaultValue)
        XCTAssertFalse(Defaults.Keys.collectScreenRecordings.defaultValue)
        XCTAssertEqual(Defaults.Keys.screenshotThumbnailSize.defaultValue, 110)
    }
}

// MARK: - Screen recordings

final class ScreenRecordingWatcherTests: XCTestCase {
    private var folder: URL!
    private var found: [URL] = []
    private var watcher: ScreenshotWatcher?
    private var savedToolCheck: (() -> Bool)!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-rec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        savedToolCheck = ClipboardScreenshotDetector.isScreenshotToolRunning
    }

    override func tearDownWithError() throws {
        watcher?.stop()
        ClipboardScreenshotDetector.isScreenshotToolRunning = savedToolCheck
        try? FileManager.default.removeItem(at: folder)
    }

    private func watch(includeRecordings: Bool) {
        found = []
        watcher?.stop()
        let watcher = ScreenshotWatcher(folder: folder, startDate: Date(), includeRecordings: includeRecordings, useSpotlight: false) { [weak self] url, _ in
            self?.found.append(url)
        }
        watcher.start()
        self.watcher = watcher
    }

    private func pump() { RunLoop.current.run(until: Date().addingTimeInterval(1.5)) }

    func testRecordingsAreCollectedOnlyWhenTurnedOnAndMadeByTheScreenshotTool() throws {
        ClipboardScreenshotDetector.isScreenshotToolRunning = { true }
        watch(includeRecordings: false)
        try Data([0]).write(to: folder.appendingPathComponent("Запись экрана 1.mov"))
        pump()
        XCTAssertEqual(found, [], "option off")

        watch(includeRecordings: true)
        try Data([0]).write(to: folder.appendingPathComponent("Запись экрана 2.mov"))
        pump()
        XCTAssertEqual(found.map(\.lastPathComponent), ["Запись экрана 2.mov"])

        ClipboardScreenshotDetector.isScreenshotToolRunning = { false }
        try Data([0]).write(to: folder.appendingPathComponent("some video.mov"))
        pump()
        XCTAssertEqual(found.count, 1, "a .mov saved by another app is not a screen recording")
    }
}

// MARK: - Batch titles

final class ScreenshotBatchTitleTests: XCTestCase {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "\(language).lproj missing")
        return try XCTUnwrap(Bundle(path: path))
    }

    private func batch(count: Int, at date: Date) -> ScreenshotBatch {
        let items = (0..<count).map { ScreenshotItem(path: "/tmp/\($0).png", capturedAt: date.addingTimeInterval(Double($0))) }
        return ScreenshotBatch(id: UUID(), items: items, lastAddedAt: items.last!.capturedAt)
    }

    func testRussianTitlesUseTodayYesterdayAndPluralForms() throws {
        let ru = try bundle("ru")
        let locale = Locale(identifier: "ru_RU")
        let now = Date()
        func title(_ count: Int, _ date: Date) -> String {
            ScreenshotBatchTitle.make(for: batch(count: count, at: date), now: now, bundle: ru, locale: locale)
        }
        XCTAssertTrue(title(1, now).hasPrefix("Сегодня "))
        XCTAssertTrue(title(1, now).hasSuffix("· 1 скриншот"))
        XCTAssertTrue(title(3, now).hasSuffix("· 3 скриншота"))
        XCTAssertTrue(title(5, now).hasSuffix("· 5 скриншотов"))
        XCTAssertTrue(title(21, now).hasSuffix("· 21 скриншот"))
        XCTAssertTrue(title(2, now.addingTimeInterval(-86_400)).hasPrefix("Вчера "))
    }

    func testEnglishTitles() throws {
        let en = try bundle("en")
        let locale = Locale(identifier: "en_US")
        let now = Date()
        let one = ScreenshotBatchTitle.make(for: batch(count: 1, at: now), now: now, bundle: en, locale: locale)
        let three = ScreenshotBatchTitle.make(for: batch(count: 3, at: now), now: now, bundle: en, locale: locale)
        XCTAssertTrue(one.hasPrefix("Today "))
        XCTAssertTrue(one.hasSuffix("· 1 screenshot"))
        XCTAssertTrue(three.hasSuffix("· 3 screenshots"))
    }
}
