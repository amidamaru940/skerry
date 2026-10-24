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
import ImageIO
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

    func testCopyInTheScreenshotsTabIsNotRecordedInTheClipboardHistory() async throws {
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
        let count = await manager.copySelected(to: pasteboard).value
        XCTAssertEqual(count, 3)
        let copied = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(copied?.map(\.lastPathComponent), ["shot-0.png", "shot-1.png", "shot-2.png"])
        XCTAssertEqual(clipboard.captureChange(from: pasteboard, sourceBundleID: nil), .ownWrite)
        settle()
        XCTAssertTrue(clipboard.clipboardHistory.isEmpty)

        // One screenshot also goes as a picture.
        manager.clearSelection()
        manager.click(manager.store.currentBatch!.items[0], extend: false)
        _ = await manager.copySelected(to: pasteboard).value
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

        // Even with "move originals to the Trash" on: a chat reads the dropped
        // file from its path later, at upload or on Send.
        let savedTrash = Defaults[.screenshotMoveOriginalsToTrash]
        Defaults[.screenshotMoveOriginalsToTrash] = true
        defer { Defaults[.screenshotMoveOriginalsToTrash] = savedTrash }
        let next = [manager.store.currentBatch!.items[0].url]
        manager.dragBegan(with: next)
        manager.dragEnded(succeeded: true)
        XCTAssertEqual(manager.store.allItems.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: next[0].path), "not trashed at the drop")
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

    func testTheActionRowSplitsTheTitle() throws {
        let ru = try bundle("ru")
        let locale = Locale(identifier: "ru_RU")
        let now = Date()
        let three = batch(count: 3, at: now)
        XCTAssertEqual(ScreenshotBatchTitle.count(for: three, bundle: ru, locale: locale), "3 снимка", "«снимки», the island's word")
        XCTAssertEqual(ScreenshotBatchTitle.count(for: batch(count: 5, at: now), bundle: ru, locale: locale), "5 снимков")
        XCTAssertTrue(ScreenshotBatchTitle.when(for: three, now: now, bundle: ru, locale: locale, lowercased: true).hasPrefix("сегодня "))
        XCTAssertTrue(ScreenshotBatchTitle.make(for: three, now: now, bundle: ru, locale: locale)
            .hasPrefix(ScreenshotBatchTitle.when(for: three, now: now, bundle: ru, locale: locale) + " · "))
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

// MARK: - Pasting a batch into a chat

/// A batch of 2+ pasted into Claude gave nothing (22.10): Chromium and
/// Electron read only the picture, and take one picture per ⌘V.
@MainActor
final class ScreenshotPasteTests: XCTestCase {
    private var folder: URL!
    private var pasteboard: NSPasteboard!
    private var savedTrusted: (() -> Bool)!
    private var savedActivate: ((NSRunningApplication) -> Void)!
    private var savedPost: (() -> Void)!
    private var savedPause: ((TimeInterval) async -> Void)!
    private var savedFrontmost: (() -> pid_t?)!
    private var savedKeyboard: (() -> Bool)!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-paste-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        savedTrusted = ClipboardPaster.isAccessibilityTrusted
        savedActivate = ClipboardPaster.activateTarget
        savedPost = ClipboardPaster.postPasteKeystroke
        savedPause = ClipboardPaster.pause
        savedFrontmost = ClipboardPaster.frontmostProcessID
        savedKeyboard = ClipboardPaster.islandHasKeyboard
        // The target (this process) stays in front and no island takes the
        // keys, unless a test says otherwise.
        ClipboardPaster.frontmostProcessID = { NSRunningApplication.current.processIdentifier }
        ClipboardPaster.islandHasKeyboard = { false }
    }

    override func tearDownWithError() throws {
        ClipboardPaster.yieldClipboard()
        ClipboardPaster.isAccessibilityTrusted = savedTrusted
        ClipboardPaster.activateTarget = savedActivate
        ClipboardPaster.postPasteKeystroke = savedPost
        ClipboardPaster.pause = savedPause
        ClipboardPaster.frontmostProcessID = savedFrontmost
        ClipboardPaster.islandHasKeyboard = savedKeyboard
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
        try super.tearDownWithError()
    }

    private func makeShots(_ count: Int) throws -> [URL] {
        try (0..<count).map { index in
            let url = folder.appendingPathComponent("shot-\(index).png")
            try testPNG().write(to: url)
            return url
        }
    }

    private func makeManager(with urls: [URL]) throws -> (ScreenshotShelfManager, ScreenshotBatch) {
        let manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))
        let start = Date()
        for (index, url) in urls.enumerated() {
            XCTAssertTrue(manager.store.add(url, capturedAt: start.addingTimeInterval(Double(index))))
        }
        return (manager, try XCTUnwrap(manager.store.batches.first))
    }

    /// Noise does not compress: a PNG of 2800 × 1000 is over 8 MB.
    private func noisePNG(width: Int, height: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                                 samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try XCTUnwrap(rep.bitmapData)
        arc4random_buf(pixels, rep.bytesPerRow * height)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testCopyPutsEveryScreenshotWithItsFileAndPicture() async throws {
        let urls = try makeShots(3)
        let (manager, _) = try makeManager(with: urls)

        let count = await manager.copy(urls, to: pasteboard).value

        XCTAssertEqual(count, 3)
        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 3, "one item per screenshot, no extra one for the marker")
        for (item, url) in zip(items, urls) {
            XCTAssertEqual(item.string(forType: .fileURL), url.absoluteString)
            let png = try XCTUnwrap(item.data(forType: .png), "Claude and Chrome read only the picture")
            XCTAssertFalse(png.isEmpty)
        }
        XCTAssertTrue(ClipboardOwnWrites.isOwnWrite(pasteboard))
    }

    func testALargeScreenshotGoesDownscaledWithTheOriginalFile() async throws {
        let url = folder.appendingPathComponent("retina.png")
        let original = try noisePNG(width: 2800, height: 1000)
        try original.write(to: url)
        XCTAssertGreaterThan(original.count, ScreenshotPasteboard.maxImageBytes)
        let (manager, _) = try makeManager(with: [url])

        let count = await manager.copy([url], to: pasteboard).value

        XCTAssertEqual(count, 1)
        let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(item.string(forType: .fileURL), url.absoluteString, "the file is still the original")
        let png = try XCTUnwrap(item.data(forType: .png))
        XCTAssertLessThanOrEqual(png.count, ScreenshotPasteboard.maxImageBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertLessThanOrEqual(max(width, height), 2560)
        XCTAssertEqual(Double(width) / Double(height), 2.8, accuracy: 0.05, "downscaled, not cropped")

        // A screenshot under the limit goes as it is.
        let small = folder.appendingPathComponent("small.png")
        try testPNG().write(to: small)
        XCTAssertEqual(ScreenshotPasteboard.pngData(for: small), try Data(contentsOf: small))
    }

    func testThreeScreenshotsArePastedOneByOne() async throws {
        XCTAssertEqual(ClipboardPaster.plan(count: 3), [
            .write(0), .wait(ClipboardPaster.pasteDelay), .pressCommandV,
            .wait(ClipboardPaster.pieceGap), .write(1), .pressCommandV,
            .wait(ClipboardPaster.pieceGap), .write(2), .pressCommandV,
        ])
        XCTAssertEqual(ClipboardPaster.plan(count: 1), [.write(0), .wait(ClipboardPaster.pasteDelay), .pressCommandV],
                       "one screenshot is pasted as before")
        XCTAssertEqual(ClipboardPaster.plan(count: 0), [])

        let urls = try makeShots(3)
        let (manager, batch) = try makeManager(with: urls)
        var events: [String] = []
        var activated: [NSRunningApplication] = []
        ClipboardPaster.isAccessibilityTrusted = { true }
        ClipboardPaster.activateTarget = { activated.append($0) }
        ClipboardPaster.pause = { seconds in events.append("wait \(seconds)") }
        ClipboardPaster.postPasteKeystroke = { [pasteboard] in
            // What the target app reads at this ⌘V.
            let items = pasteboard?.pasteboardItems ?? []
            let name = items.first?.string(forType: .fileURL).flatMap { URL(string: $0) }?.lastPathComponent ?? "?"
            let hasPicture = items.first?.data(forType: .png)?.isEmpty == false
            events.append("⌘V \(items.count) \(name) \(hasPicture)")
        }

        var closed = 0
        let result = manager.paste(batch: batch, pasteboard: pasteboard, target: NSRunningApplication.current) { closed += 1 }

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(activated, [NSRunningApplication.current])
        let run = try XCTUnwrap(ClipboardPaster.pasteRun)
        await run.value
        XCTAssertEqual(events, [
            "wait \(ClipboardPaster.pasteDelay)", "⌘V 1 shot-0.png true",
            "wait \(ClipboardPaster.pieceGap)", "⌘V 1 shot-1.png true",
            "wait \(ClipboardPaster.pieceGap)", "⌘V 1 shot-2.png true",
        ])
        XCTAssertNil(ClipboardPaster.pasteRun, "nothing keeps running after the last ⌘V")
        // The clipboard is left with the last screenshot.
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.string(forType: .fileURL), urls[2].absoluteString)
        XCTAssertTrue(ClipboardOwnWrites.isOwnWrite(pasteboard))
    }

    func testABatchWhoseFilesAreGonePastesNothing() async throws {
        let urls = try makeShots(2)
        let (manager, batch) = try makeManager(with: urls)
        for url in urls { try FileManager.default.removeItem(at: url) }
        pasteboard.clearContents()
        pasteboard.setString("copied earlier", forType: .string)
        var pressed = 0
        var activated = 0
        ClipboardPaster.isAccessibilityTrusted = { true }
        ClipboardPaster.activateTarget = { _ in activated += 1 }
        ClipboardPaster.pause = { _ in }
        ClipboardPaster.postPasteKeystroke = { pressed += 1 }

        var closed = false
        let result = manager.paste(batch: batch, pasteboard: pasteboard, target: NSRunningApplication.current) { closed = true }

        XCTAssertEqual(result, .nothingCopied)
        XCTAssertFalse(closed, "the island stays open to say so")
        XCTAssertNil(ClipboardPaster.pasteRun)
        await Task.yield()
        XCTAssertEqual(pressed, 0, "⌘V would paste what was copied earlier")
        XCTAssertEqual(activated, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "copied earlier")

        let count = await manager.copy(urls, to: pasteboard).value
        XCTAssertEqual(count, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "copied earlier", "an empty copy leaves the clipboard alone")
    }

    // MARK: A run that stops

    /// The files on the clipboard, by name.
    private static func names(on pasteboard: NSPasteboard) -> [String] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            item.string(forType: .fileURL).flatMap { URL(string: $0) }?.lastPathComponent
        }
    }

    func testStoppingARunMidWayPressesNoFurtherCommandV() async throws {
        let urls = try makeShots(3)
        let (manager, batch) = try makeManager(with: urls)
        var presses: [[String]] = []
        var pauses = 0
        var stopped: [Int] = []
        ClipboardPaster.isAccessibilityTrusted = { true }
        ClipboardPaster.activateTarget = { _ in }
        ClipboardPaster.postPasteKeystroke = { [pasteboard] in presses.append(Self.names(on: pasteboard!)) }
        ClipboardPaster.pause = { @MainActor _ in
            pauses += 1
            // In the gap after the first ⌘V a newer paste or copy takes over.
            if pauses == 2 { ClipboardPaster.stopPasting() }
        }

        let result = manager.paste(batch: batch, pasteboard: pasteboard, target: NSRunningApplication.current,
                                   onStopped: { stopped.append($0) }) {}

        XCTAssertEqual(result, .pasted)
        let run = try XCTUnwrap(ClipboardPaster.pasteRun)
        await run.value
        XCTAssertEqual(presses, [["shot-0.png"]], "no ⌘V after the stop")
        XCTAssertEqual(Self.names(on: pasteboard), ["shot-0.png"], "nothing more is written: the clipboard is the newer one's")
        XCTAssertEqual(stopped, [])
        XCTAssertNil(ClipboardPaster.pasteRun)
    }

    /// After the first ⌘V, `interrupt` makes a ⌘V unsafe: the run presses no
    /// more, copies the two shots left together and says so.
    private func assertTheRunStopsAndCopiesTheRest(
        _ why: String, file: StaticString = #filePath, line: UInt = #line,
        isIslandOpen: @escaping @MainActor () -> Bool = { false }, interrupt: @escaping () -> Void
    ) async throws {
        pasteboard.clearContents()
        let urls = try makeShots(3)
        let (manager, batch) = try makeManager(with: urls)
        var presses: [[String]] = []
        var stopped: [Int] = []
        ClipboardPaster.isAccessibilityTrusted = { true }
        ClipboardPaster.activateTarget = { _ in }
        ClipboardPaster.pause = { _ in }
        ClipboardPaster.postPasteKeystroke = { [pasteboard] in
            presses.append(Self.names(on: pasteboard!))
            interrupt()
        }

        let result = manager.paste(batch: batch, pasteboard: pasteboard, target: NSRunningApplication.current,
                                   isIslandOpen: isIslandOpen, onStopped: { stopped.append($0) }) {}

        XCTAssertEqual(result, .pasted, why, file: file, line: line)
        let run = try XCTUnwrap(ClipboardPaster.pasteRun, why, file: file, line: line)
        await run.value
        XCTAssertEqual(presses, [["shot-0.png"]], "\(why): no screenshot goes anywhere else", file: file, line: line)
        XCTAssertEqual(Self.names(on: pasteboard), ["shot-1.png", "shot-2.png"], "\(why): the rest wait for ⌘V", file: file, line: line)
        XCTAssertTrue((pasteboard.pasteboardItems ?? []).allSatisfy { $0.data(forType: .png)?.isEmpty == false },
                      "\(why): each still goes with its picture", file: file, line: line)
        XCTAssertTrue(ClipboardOwnWrites.isOwnWrite(pasteboard), why, file: file, line: line)
        XCTAssertEqual(stopped, [2], "\(why): the hint is shown", file: file, line: line)
    }

    func testAnotherAppComingForwardStopsTheRun() async throws {
        var front = NSRunningApplication.current.processIdentifier
        ClipboardPaster.frontmostProcessID = { front }
        try await assertTheRunStopsAndCopiesTheRest("another app in front") { front = 1 }
    }

    func testTheIslandOpeningStopsTheRun() async throws {
        var open = false
        try await assertTheRunStopsAndCopiesTheRest("the island opened", isIslandOpen: { open }) { open = true }
        var keyboard = false
        ClipboardPaster.islandHasKeyboard = { keyboard }
        try await assertTheRunStopsAndCopiesTheRest("the island took the keyboard") { keyboard = true }
    }

    func testCopyingAHistoryEntryDuringARunStopsIt() async throws {
        let urls = try makeShots(3)
        let (manager, batch) = try makeManager(with: urls)
        var presses = 0
        var stopped: [Int] = []
        ClipboardPaster.isAccessibilityTrusted = { true }
        ClipboardPaster.activateTarget = { _ in }
        ClipboardPaster.pause = { _ in }
        ClipboardPaster.postPasteKeystroke = { [pasteboard] in
            presses += 1
            // Right after the first picture the user copies a history entry.
            ClipboardManager.shared.copyToClipboard(ClipboardItem(stringData: "my own copy", type: .text), to: pasteboard!)
        }

        _ = manager.paste(batch: batch, pasteboard: pasteboard, target: NSRunningApplication.current,
                          onStopped: { stopped.append($0) }) {}
        let run = try XCTUnwrap(ClipboardPaster.pasteRun)
        await run.value

        XCTAssertEqual(presses, 1)
        XCTAssertNil(ClipboardPaster.pasteRun)
        XCTAssertEqual(pasteboard.string(forType: .string), "my own copy", "no later step overwrites it")
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(stopped, [], "not a stop to recover from: the clipboard is the user's")
    }

    func testCopyingAHistoryEntryOrAColourStopsAScreenshotCopyBeingPrepared() async throws {
        let urls = try makeShots(3)
        let (manager, _) = try makeManager(with: urls)

        let first = manager.copy(urls, to: pasteboard)
        ClipboardManager.shared.copyToClipboard(ClipboardItem(stringData: "my own copy", type: .text), to: pasteboard)
        let firstCount = await first.value
        XCTAssertEqual(firstCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "my own copy")
        XCTAssertEqual(Self.names(on: pasteboard), [])

        let second = manager.copy(urls, to: pasteboard)
        ColorPickerManager.shared.copyToClipboard("#5BBEEB", to: pasteboard)
        let secondCount = await second.value
        XCTAssertEqual(secondCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "#5BBEEB")
        XCTAssertEqual(Self.names(on: pasteboard), [])
    }

    func testWithoutAccessibilityAllAreCopiedTogetherAndNothingIsPressed() async throws {
        let urls = try makeShots(3)
        let (manager, batch) = try makeManager(with: urls)
        var pressed = 0
        var activated = 0
        var closed = 0
        ClipboardPaster.isAccessibilityTrusted = { false }
        ClipboardPaster.activateTarget = { _ in activated += 1 }
        ClipboardPaster.pause = { _ in }
        ClipboardPaster.postPasteKeystroke = { pressed += 1 }

        let result = manager.paste(batch: batch, pasteboard: pasteboard, target: NSRunningApplication.current) { closed += 1 }

        XCTAssertEqual(result, .copiedOnly)
        let run = try XCTUnwrap(ClipboardPaster.pasteRun)
        await run.value
        XCTAssertEqual(Self.names(on: pasteboard), ["shot-0.png", "shot-1.png", "shot-2.png"])
        XCTAssertTrue((pasteboard.pasteboardItems ?? []).allSatisfy { $0.data(forType: .png)?.isEmpty == false })
        XCTAssertTrue(ClipboardOwnWrites.isOwnWrite(pasteboard))
        XCTAssertEqual(pressed, 0, "the user presses ⌘V")
        XCTAssertEqual(activated, 0)
        XCTAssertEqual(closed, 0, "the island stays open to say so")
    }
}
