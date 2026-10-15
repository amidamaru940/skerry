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
import SwiftUI
import XCTest

/// Step D4: the Clipboard tab with the screenshots in it.
@MainActor
final class BufferTabTests: XCTestCase {
    // MARK: Segments and the batch strip

    func testSegmentsFollowWhatIsTurnedOn() {
        XCTAssertEqual(BufferSegment.available(clipboard: true, screenshots: true), [.all, .screenshots, .text, .links, .files])
        XCTAssertEqual(BufferSegment.available(clipboard: false, screenshots: true), [.screenshots])
        XCTAssertEqual(BufferSegment.available(clipboard: true, screenshots: false), [.all, .text, .links, .files])
        XCTAssertEqual(BufferSegment.available(clipboard: false, screenshots: false), [])
        XCTAssertEqual(BufferSegment.resolve(.text, available: [.screenshots]), .screenshots)
        XCTAssertEqual(BufferSegment.resolve(.links, available: [.all, .links]), .links)
        XCTAssertNil(BufferSegment.resolve(.all, available: []))
        XCTAssertNil(BufferSegment.screenshots.clipboardFilter)
        XCTAssertEqual(BufferSegment.files.clipboardFilter, .files)
    }

    func testTheLatestBatchSitsOnTopOfEverythingForADay() {
        let now = Date()
        XCTAssertTrue(BufferLayout.showsBatchStrip(segment: .all, lastAddedAt: now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(BufferLayout.showsBatchStrip(segment: .all, lastAddedAt: now.addingTimeInterval(-25 * 3600), now: now))
        XCTAssertFalse(BufferLayout.showsBatchStrip(segment: .screenshots, lastAddedAt: now, now: now), "the grid shows it already")
        XCTAssertFalse(BufferLayout.showsBatchStrip(segment: .text, lastAddedAt: now, now: now))
        XCTAssertFalse(BufferLayout.showsBatchStrip(segment: .all, lastAddedAt: nil, now: now))
    }

    func testThePasteButtonNamesTheAppOrSaysCopy() {
        let paste = BufferLayout.pasteTitle(count: 3, target: "Claude", canPaste: true)
        XCTAssertTrue(paste.contains("Claude") && paste.contains("3"), paste)
        let copy = BufferLayout.pasteTitle(count: 3, target: "Claude", canPaste: false)
        XCTAssertFalse(copy.contains("Claude"), "without Accessibility it can only copy")
        XCTAssertTrue(copy.contains("3"))
        XCTAssertEqual(BufferLayout.pasteTitle(count: 1, target: nil, canPaste: true), BufferLayout.pasteTitle(count: 1, target: nil, canPaste: false))
    }

    // MARK: Pasting a batch

    private func makeManager() throws -> (ScreenshotShelfManager, [URL], URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-buffer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))
        let start = Date()
        var urls: [URL] = []
        for index in 0..<3 {
            let url = folder.appendingPathComponent("shot-\(index).png")
            try Data([UInt8(index)]).write(to: url)
            XCTAssertTrue(manager.store.add(url, capturedAt: start.addingTimeInterval(Double(index))))
            urls.append(url)
        }
        return (manager, urls, folder)
    }

    func testPasteTakesTheSelectedScreenshotsOrTheWholeBatch() throws {
        let (manager, urls, folder) = try makeManager()
        defer { try? FileManager.default.removeItem(at: folder) }
        let batch = try XCTUnwrap(manager.store.batches.first)
        XCTAssertEqual(manager.pasteURLs(for: batch), urls, "nothing chosen: all, in capture order")

        let middle = try XCTUnwrap(batch.items.first { $0.url == urls[1] })
        manager.click(middle, extend: false)
        XCTAssertEqual(manager.pasteURLs(for: batch), [urls[1]])
        XCTAssertEqual(manager.selectedCount(in: batch), 1)
        // The second click of a double-click keeps it chosen (it used to deselect it).
        manager.click(middle, extend: false, double: true)
        XCTAssertEqual(manager.pasteURLs(for: batch), [urls[1]])
    }

    func testPastingABatchCopiesItAsOurOwnAndPressesCommandV() throws {
        let (manager, urls, folder) = try makeManager()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.amidamaru940.skerry.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let savedTrusted = ClipboardPaster.isAccessibilityTrusted
        let savedActivate = ClipboardPaster.activateTarget
        let savedPost = ClipboardPaster.postPasteKeystroke
        defer {
            ClipboardPaster.isAccessibilityTrusted = savedTrusted
            ClipboardPaster.activateTarget = savedActivate
            ClipboardPaster.postPasteKeystroke = savedPost
        }
        let pressed = expectation(description: "⌘V pressed")
        ClipboardPaster.isAccessibilityTrusted = { true }
        ClipboardPaster.activateTarget = { _ in }
        ClipboardPaster.postPasteKeystroke = { pressed.fulfill() }

        var closed = false
        let batch = try XCTUnwrap(manager.store.batches.first)
        let result = manager.paste(batch: batch, pasteboard: pasteboard, target: NSRunningApplication.current) { closed = true }

        XCTAssertEqual(result, .pasted)
        XCTAssertTrue(closed)
        let copied = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(copied?.map(\.lastPathComponent), urls.map(\.lastPathComponent))
        XCTAssertTrue(ClipboardOwnWrites.isOwnWrite(pasteboard), "the history does not record it")
        wait(for: [pressed], timeout: 2)
    }

    // MARK: Cards

    func testCardsSayWhatAFileOrLinkIs() {
        XCTAssertEqual(ClipboardCardText.fileTitle(names: ["report.pdf"]), "report.pdf")
        XCTAssertTrue(ClipboardCardText.fileTitle(names: ["a.png", "b.png", "c.png"]).contains("3"))
        let link = ClipboardCardText.link("https://www.example.org/docs/start?tab=2")
        XCTAssertEqual(link.host, "example.org")
        XCTAssertEqual(link.rest, "/docs/start?tab=2")
        XCTAssertEqual(ClipboardCardText.link("https://example.org/").rest, "")
        XCTAssertEqual(ClipboardCardText.link("https://ru.wikipedia.org/wiki/%D0%9C%D0%BE%D1%81%D0%BA%D0%B2%D0%B0").rest, "/wiki/Москва")
        XCTAssertEqual(ClipboardCardText.link("not a link").host, "not a link")
    }

    func testAPictureDragsAtItsOwnShape() {
        XCTAssertEqual(ClipboardDragPreview.size(for: CGSize(width: 1200, height: 600)), NSSize(width: 120, height: 60))
        XCTAssertEqual(ClipboardDragPreview.size(for: CGSize(width: 40, height: 80)), NSSize(width: 40, height: 80))
        XCTAssertEqual(ClipboardDragPreview.size(for: .zero), NSSize(width: 32, height: 32))
    }

    // MARK: One tab instead of two

    func testScreenshotsAreShownInTheClipboardTab() {
        XCTAssertTrue(NotchTab.screenshots.isMergedIntoClipboard)
        XCTAssertEqual(NotchTab.screenshots.shownAs, .clipboard)
        XCTAssertEqual(NotchTab.shelf.shownAs, .shelf)
        XCTAssertEqual(IslandKeyboard.action(for: .close, current: .clipboard, visible: [.clipboard], hasScreenshotSelection: true),
                       .clearScreenshotSelection, "Esc first clears the chosen screenshots")
        XCTAssertEqual(IslandKeyboard.action(for: .close, current: .clipboard, visible: [.clipboard], hasScreenshotSelection: false), .close)
    }

    // MARK: Drawing

    func testTheBatchStripAndCardsDraw() throws {
        let card = ClipboardCard(item: ClipboardItem(stringData: "https://www.example.org/docs/start", type: .url), number: 1,
                                 isHovered: false, isSelected: false, justCopied: false)
        let files = ClipboardCard(item: ClipboardItem(fileURLs: ["file:///tmp/a.png", "file:///tmp/b.png"]), number: 2,
                                  isHovered: true, isSelected: true, justCopied: false)
        let pieces: [(String, AnyView, CGSize)] = [
            ("card-link", AnyView(card), CGSize(width: 220, height: 70)),
            ("card-files", AnyView(files), CGSize(width: 220, height: 70)),
            ("toast", AnyView(DSToastView(text: BufferTabState.copiedHint, tone: .warning)), CGSize(width: 560, height: 40)),
            ("segments", AnyView(DSSegmented(options: BufferSegment.allCases.map { (value: $0, title: $0.title) }, selection: .constant(.all))), CGSize(width: 420, height: 30)),
        ]
        let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        for (name, view, size) in pieces {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).padding(8).background(Color.black).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, name)
            XCTAssertGreaterThan(image.size.width, 0)
            if let folder, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("\(name).png"))
            }
        }
    }
}
