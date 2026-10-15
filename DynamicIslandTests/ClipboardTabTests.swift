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

private func pngData() -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Filters, search, labels, keys

final class ClipboardFilteringTests: XCTestCase {
    private let longText = String(repeating: "lorem ", count: 20) + "Третьяковская галерея"
    private lazy var items: [ClipboardItem] = [
        ClipboardItem(stringData: longText, type: .text),
        ClipboardItem(stringData: "https://example.org/Card/123", type: .url),
        ClipboardItem(fileURLs: [URL(fileURLWithPath: "/tmp/Отчёт за квартал.pdf").absoluteString]),
        ClipboardItem(rtfData: Data("{\\rtf1 x}".utf8), plainText: "formatted note"),
    ]

    func testFiltersByKind() {
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .all, query: "").count, 4)
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .text, query: "").map(\.type), [.text, .rtf])
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .links, query: "").map(\.type), [.url])
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .files, query: "").map(\.type), [.file])
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .images, query: "").count, 0)
    }

    func testSearchesTheFullTextAndFileNamesIgnoringCase() {
        XCTAssertGreaterThan(longText.count, 50, "the match lies beyond the 50-character preview")
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .all, query: "третьяковская").map(\.type), [.text])
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .all, query: "отчёт").map(\.type), [.file])
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .all, query: "EXAMPLE.ORG").map(\.type), [.url])
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .text, query: "example").count, 0, "filter and search combine")
        XCTAssertEqual(ClipboardFiltering.apply(items, filter: .all, query: "   ").count, 4)
    }

    func testOneTimeCodesAreFourToEightDigitsOnly() {
        for code in ["1234", "123456", " 987654 ", "12345678"] {
            XCTAssertTrue(ClipboardItem(stringData: code, type: .text).isOneTimeCode, code)
        }
        for other in ["123", "123456789", "12 34", "code 1234", "１２３４", "12a4"] {
            XCTAssertFalse(ClipboardItem(stringData: other, type: .text).isOneTimeCode, other)
        }
        XCTAssertFalse(ClipboardItem(stringData: "1234", type: .url).isOneTimeCode)
    }

    func testKeyActions() {
        XCTAssertEqual(ClipboardKeyAction(keyCode: 36, characters: "\r", modifiers: []), .pasteSelected(plainText: false))
        XCTAssertEqual(ClipboardKeyAction(keyCode: 76, characters: "\r", modifiers: [.shift]), .pasteSelected(plainText: true))
        XCTAssertEqual(ClipboardKeyAction(keyCode: 18, characters: "1", modifiers: [.command]), .pasteNumber(0, plainText: false))
        XCTAssertEqual(ClipboardKeyAction(keyCode: 25, characters: "9", modifiers: [.command, .shift]), .pasteNumber(8, plainText: true))
        XCTAssertNil(ClipboardKeyAction(keyCode: 18, characters: "1", modifiers: []), "a digit without ⌘ is typing")
        XCTAssertNil(ClipboardKeyAction(keyCode: 0, characters: "a", modifiers: [.command]))
        XCTAssertNil(ClipboardKeyAction(keyCode: 36, characters: "\r", modifiers: [.command]))
    }

    func testCardTimeLabels() throws {
        let now = Date()
        let ru = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"))))
        let locale = Locale(identifier: "ru_RU")
        let today = DayTimeLabel.make(for: now, now: now, bundle: ru, locale: locale)
        XCTAssertFalse(today.contains("Сегодня"), "today shows the time only")
        XCTAssertTrue(today.contains(":"))
        XCTAssertTrue(DayTimeLabel.make(for: now.addingTimeInterval(-86_400), now: now, bundle: ru, locale: locale).hasPrefix("Вчера "))
    }

    func testClipboardDefaults() {
        XCTAssertFalse(Defaults.Keys.clipboardPersistPinned.defaultValue)
        XCTAssertTrue(Defaults.Keys.clipboardOneTimeCodeExpiry.defaultValue)
    }
}

// MARK: - Manager: source app, codes, copy back, paste

@MainActor
final class ClipboardTabManagerTests: XCTestCase {
    private let manager = ClipboardManager.shared
    private var pasteboard: NSPasteboard!
    private var directory: URL!
    private var savedHistory: [ClipboardItem] = []
    private var savedPinned: [ClipboardItem] = []
    private var savedPersist = false
    private var savedPinnedSetting = false
    private var savedCodes = true
    private var savedAutoClear = 24

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.amidamaru940.skerry.tests.\(UUID().uuidString)"))
        savedHistory = manager.clipboardHistory
        savedPinned = manager.pinnedItems
        savedPersist = Defaults[.persistClipboardHistory]
        savedPinnedSetting = Defaults[.clipboardPersistPinned]
        savedCodes = Defaults[.clipboardOneTimeCodeExpiry]
        savedAutoClear = Defaults[.clipboardAutoClearHours]
        Defaults[.persistClipboardHistory] = false
        Defaults[.clipboardPersistPinned] = false
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("amg-cliptab-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ClipboardManager.directoryOverride = directory
        manager.clipboardHistory = []
        manager.pinnedItems = []
    }

    override func tearDown() {
        manager.clipboardHistory = savedHistory
        manager.pinnedItems = savedPinned
        Defaults[.persistClipboardHistory] = savedPersist
        Defaults[.clipboardPersistPinned] = savedPinnedSetting
        Defaults[.clipboardOneTimeCodeExpiry] = savedCodes
        Defaults[.clipboardAutoClearHours] = savedAutoClear
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        ClipboardManager.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }

    func testTheSourceAppIsRecorded() {
        pasteboard.clearContents()
        pasteboard.setString("from mail", forType: .string)
        manager.captureChange(from: pasteboard, sourceBundleID: "com.apple.mail")
        settle()
        XCTAssertEqual(manager.clipboardHistory.first?.sourceBundleID, "com.apple.mail")
    }

    func testOneTimeCodesLeaveAfterTwoMinutes() {
        Defaults[.clipboardAutoClearHours] = 0
        Defaults[.clipboardOneTimeCodeExpiry] = true
        manager.clipboardHistory = [
            ClipboardItem(stringData: "482913", type: .text),
            ClipboardItem(stringData: "meeting at 10", type: .text),
            ClipboardItem(stringData: "123", type: .text),
        ]

        manager.purgeExpiredItems(now: Date().addingTimeInterval(100))
        XCTAssertEqual(manager.clipboardHistory.count, 3, "younger than 2 minutes")

        manager.purgeExpiredItems(now: Date().addingTimeInterval(121))
        XCTAssertEqual(manager.clipboardHistory.compactMap(\.stringData), ["meeting at 10", "123"])
    }

    func testOneTimeCodesStayWhenTheOptionIsOff() {
        Defaults[.clipboardAutoClearHours] = 0
        Defaults[.clipboardOneTimeCodeExpiry] = false
        manager.clipboardHistory = [ClipboardItem(stringData: "482913", type: .text)]
        manager.purgeExpiredItems(now: Date().addingTimeInterval(600))
        XCTAssertEqual(manager.clipboardHistory.count, 1)
    }

    func testCopyingBackMovesTheSameEntryToTheTopWithoutADuplicate() {
        let first = ClipboardItem(stringData: "first", type: .text)
        let second = ClipboardItem(stringData: "second", type: .text)
        manager.clipboardHistory = [first, second]

        manager.copyToClipboard(second, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "second")
        XCTAssertEqual(manager.captureChange(from: pasteboard, sourceBundleID: nil), .ownWrite)
        settle()

        XCTAssertEqual(manager.clipboardHistory.map(\.id), [second.id, first.id], "same entries, same ids, new order")
    }

    func testCopyingBackAPinnedItemAddsNothingToTheHistory() {
        let pinned = ClipboardItem(stringData: "pinned text", type: .text)
        manager.pinnedItems = [pinned]

        manager.copyToClipboard(pinned, to: pasteboard)
        manager.captureChange(from: pasteboard, sourceBundleID: nil)
        settle()

        XCTAssertTrue(manager.clipboardHistory.isEmpty)
        XCTAssertEqual(manager.pinnedItems.map(\.id), [pinned.id])
    }

    // MARK: Step D4

    func testCopyingAgainInAnotherAppMovesTheEntryToTheTop() {
        manager.clipboardHistory = [
            ClipboardItem(stringData: "first", type: .text),
            ClipboardItem(stringData: "second", type: .text),
        ]
        pasteboard.clearContents()
        pasteboard.setString("second", forType: .string)
        manager.captureChange(from: pasteboard, sourceBundleID: "com.apple.Safari")
        settle()
        XCTAssertEqual(manager.clipboardHistory.compactMap(\.stringData), ["second", "first"], "no duplicate, on top")
        XCTAssertEqual(manager.clipboardHistory.first?.sourceBundleID, "com.apple.Safari")
    }

    func testARepeatedPictureLeavesNoStrayFile() throws {
        Defaults[.persistClipboardHistory] = true
        settle()   // let the manager react to the switch before copying
        for _ in 0..<2 {
            pasteboard.clearContents()
            pasteboard.setData(pngData(), forType: .png)
            manager.captureChange(from: pasteboard, sourceBundleID: nil)
            settle()
        }
        XCTAssertEqual(manager.clipboardHistory.count, 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("clipboard_image_") }
        XCTAssertEqual(files.count, 1, "the older copy's picture file goes with it")
    }

    func testSeveralPicturesFromFinderAreAllKept() throws {
        let one = directory.appendingPathComponent("one.png")
        let two = directory.appendingPathComponent("two.png")
        try pngData().write(to: one)
        try pngData().write(to: two)
        pasteboard.clearContents()
        pasteboard.writeObjects([one as NSURL, two as NSURL])
        manager.captureChange(from: pasteboard, sourceBundleID: "com.apple.finder")
        settle()
        XCTAssertEqual(manager.clipboardHistory.first?.type, .file)
        XCTAssertEqual(manager.clipboardHistory.first?.fileURLs?.count, 2, "upstream kept only the first picture")
        XCTAssertTrue(ClipboardFinderCopy.keepsAsPicture(fileCount: 1, imageCount: 1))
        XCTAssertFalse(ClipboardFinderCopy.keepsAsPicture(fileCount: 2, imageCount: 2))
        XCTAssertFalse(ClipboardFinderCopy.keepsAsPicture(fileCount: 1, imageCount: 0))
    }

    func testColoursFromThePickerStayOutOfTheHistory() {
        ColorPickerManager.shared.copyToClipboard("#5BBEEB", to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "#5BBEEB")
        XCTAssertEqual(manager.captureChange(from: pasteboard, sourceBundleID: nil), .ownWrite)
        settle()
        XCTAssertTrue(manager.clipboardHistory.isEmpty)
    }

    func testWithoutAccessibilityTheIslandStaysOpenToSayPressCommandV() {
        let savedTrusted = ClipboardPaster.isAccessibilityTrusted
        defer { ClipboardPaster.isAccessibilityTrusted = savedTrusted }
        ClipboardPaster.isAccessibilityTrusted = { false }
        var closed = false
        let result = ClipboardPaster.paste(ClipboardItem(stringData: "x", type: .text), plainText: false, manager: manager,
                                           pasteboard: pasteboard, target: NSRunningApplication.current, closeIsland: { closed = true })
        XCTAssertEqual(result, .copiedOnly)
        XCTAssertFalse(closed, "a closed island could not show the hint")
    }

    func testPlainTextCopyDropsFormatting() {
        let rich = ClipboardItem(rtfData: Data("{\\rtf1 bold}".utf8), plainText: "bold")
        manager.copyToClipboard(rich, plainText: true, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "bold")
        XCTAssertNil(pasteboard.data(forType: .rtf))

        manager.copyToClipboard(rich, plainText: false, to: pasteboard)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))
    }

    func testPastingCopiesClosesTheIslandAndPressesCommandV() {
        let savedTrusted = ClipboardPaster.isAccessibilityTrusted
        let savedActivate = ClipboardPaster.activateTarget
        let savedPost = ClipboardPaster.postPasteKeystroke
        defer {
            ClipboardPaster.isAccessibilityTrusted = savedTrusted
            ClipboardPaster.activateTarget = savedActivate
            ClipboardPaster.postPasteKeystroke = savedPost
        }
        var activated: NSRunningApplication?
        let pressed = expectation(description: "⌘V pressed")
        ClipboardPaster.isAccessibilityTrusted = { true }
        ClipboardPaster.activateTarget = { activated = $0 }
        ClipboardPaster.postPasteKeystroke = { pressed.fulfill() }

        var closed = false
        let item = ClipboardItem(stringData: "paste me", type: .text)
        let result = ClipboardPaster.paste(item, plainText: false, manager: manager, pasteboard: pasteboard,
                                           target: NSRunningApplication.current, closeIsland: { closed = true })

        XCTAssertEqual(result, .pasted)
        XCTAssertTrue(closed)
        XCTAssertEqual(activated, NSRunningApplication.current)
        XCTAssertEqual(pasteboard.string(forType: .string), "paste me")
        XCTAssertTrue(ClipboardOwnWrites.isOwnWrite(pasteboard), "the paste is not recorded as a new copy")
        wait(for: [pressed], timeout: 2)
    }

    func testWithoutAccessibilityTheItemIsOnlyCopied() {
        let savedTrusted = ClipboardPaster.isAccessibilityTrusted
        let savedPost = ClipboardPaster.postPasteKeystroke
        defer {
            ClipboardPaster.isAccessibilityTrusted = savedTrusted
            ClipboardPaster.postPasteKeystroke = savedPost
        }
        ClipboardPaster.isAccessibilityTrusted = { false }
        var pressed = false
        ClipboardPaster.postPasteKeystroke = { pressed = true }

        let result = ClipboardPaster.paste(ClipboardItem(stringData: "only copied", type: .text), plainText: false,
                                           manager: manager, pasteboard: pasteboard, target: NSRunningApplication.current,
                                           closeIsland: {})
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        XCTAssertEqual(result, .copiedOnly)
        XCTAssertFalse(pressed)
        XCTAssertEqual(pasteboard.string(forType: .string), "only copied")
    }

    func testTheIslandItselfIsNeverThePasteTarget() {
        ClipboardPaster.remember(NSRunningApplication.current)
        XCTAssertNotEqual(ClipboardPaster.lastExternalApp?.bundleIdentifier, Bundle.main.bundleIdentifier)
    }
}

// MARK: - Dragging out

final class ClipboardDragTests: XCTestCase {
    private func legacyCopies() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("clipboard_image_") })
    }

    func testAPictureDragsAsPNGAndAFilePromiseWithoutTemporaryFiles() throws {
        let savedPersist = Defaults[.persistClipboardHistory]
        Defaults[.persistClipboardHistory] = false
        defer { Defaults[.persistClipboardHistory] = savedPersist }
        let before = legacyCopies()

        let png = pngData()
        let item = ClipboardItem(imageData: png)
        XCTAssertNil(item.imageFileName, "a memory-only picture")
        let writers = ClipboardDragWriters.writers(for: item)
        let provider = try XCTUnwrap(writers.first as? ClipboardImagePromiseProvider)
        XCTAssertEqual(writers.count, 1)

        let probe = NSPasteboard(name: NSPasteboard.Name("io.github.amidamaru940.skerry.tests.\(UUID().uuidString)"))
        defer { probe.releaseGlobally() }
        XCTAssertTrue(provider.writableTypes(for: probe).contains(.png))
        XCTAssertEqual(provider.pasteboardPropertyList(forType: .png) as? Data, png, "the picture itself, not its preview text")

        // Dropping in a folder writes the file there, and only there.
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("amg-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        let target = destination.appendingPathComponent(provider.filePromiseProvider(provider, fileNameForType: provider.fileType))
        let written = expectation(description: "promise written")
        provider.filePromiseProvider(provider, writePromiseTo: target) { error in
            XCTAssertNil(error)
            written.fulfill()
        }
        wait(for: [written], timeout: 2)
        XCTAssertEqual(try Data(contentsOf: target), png)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 1)

        XCTAssertEqual(legacyCopies(), before, "no temporary copies of clipboard pictures")
    }

    func testTextAndFilesDragAsThemselves() throws {
        let text = ClipboardDragWriters.writers(for: ClipboardItem(stringData: "hello", type: .text))
        XCTAssertEqual((text.first as? NSPasteboardItem)?.string(forType: .string), "hello")

        let files = ["/tmp/a.pdf", "/tmp/b.pdf"].map { URL(fileURLWithPath: $0).absoluteString }
        let writers = ClipboardDragWriters.writers(for: ClipboardItem(fileURLs: files))
        XCTAssertEqual(writers.count, 2, "a multi-file entry drags every file")
        XCTAssertTrue(writers.allSatisfy { $0 is NSURL })
    }

    func testLeftoverCopiesFromUpstreamAreRemovedAtLaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([1]).write(to: folder.appendingPathComponent("clipboard_image_ABC.png"))
        try Data([2]).write(to: folder.appendingPathComponent("unrelated.png"))

        ClipboardTemporaryFiles.removeLegacyDragCopies(in: folder)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["unrelated.png"])
    }
}
