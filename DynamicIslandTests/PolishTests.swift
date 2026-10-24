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

/// Step D8: the remaining points of the audit.
@MainActor
final class PolishTests: XCTestCase {
    private func color(_ hex: UInt32) -> PickedColor {
        PickedColor(nsColor: NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                                     blue: CGFloat(hex & 0xFF) / 255, alpha: 1), point: .zero)
    }

    func testTheColourHistoryKeepsEachColourOnceAndHonoursItsSize() {
        var history: [PickedColor] = []
        history = ColorHistoryRules.adding(color(0x5BBEEB), to: history, limit: 3)
        history = ColorHistoryRules.adding(color(0xFF0000), to: history, limit: 3)
        history = ColorHistoryRules.adding(color(0x5BBEEB), to: history, limit: 3)
        XCTAssertEqual(history.map(\.hexString), [color(0x5BBEEB).hexString, color(0xFF0000).hexString], "picked again: on top, once")
        history = ColorHistoryRules.adding(color(0x00FF00), to: history, limit: 3)
        history = ColorHistoryRules.adding(color(0x0000FF), to: history, limit: 3)
        XCTAssertEqual(history.count, 3, "the setting, not a fixed 50")
        XCTAssertEqual(Defaults.Keys.colorHistorySize.defaultValue, 10)
    }

    func testRemovingScreenshotsAsksFirstOnlyWhenFilesWouldGoToTheTrash() throws {
        let saved = Defaults[.screenshotMoveOriginalsToTrash]
        defer { Defaults[.screenshotMoveOriginalsToTrash] = saved }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-trash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))
        let shot = folder.appendingPathComponent("a.png")
        try Data([1]).write(to: shot)
        XCTAssertTrue(manager.store.add(shot, capturedAt: Date()))

        Defaults[.screenshotMoveOriginalsToTrash] = true
        manager.requestRemoval([shot.path])
        XCTAssertEqual(manager.pendingRemoval, .items([shot.path]), "waits for a yes")
        XCTAssertFalse(manager.store.isEmpty)
        manager.pendingRemoval = nil   // "Cancel"
        XCTAssertFalse(manager.store.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shot.path), "nothing went to the Trash")

        Defaults[.screenshotMoveOriginalsToTrash] = false
        manager.requestRemoval([shot.path])
        XCTAssertNil(manager.pendingRemoval, "only the batch forgets it: no question")
        XCTAssertTrue(manager.store.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shot.path), "the file stays")
    }

    func testCopyFeedbackSaysHowMany() {
        XCTAssertTrue(BufferTabState.copiedScreenshots(3).contains("3"))
    }

    func testAfterClearingTheNewestBatchTheNextScreenshotStartsANewOne() throws {
        let store = ScreenshotBatchStore(fileURL: nil, batchGap: { 900 })
        let start = Date()
        XCTAssertTrue(store.add(URL(fileURLWithPath: "/tmp/amg-a.png"), capturedAt: start))
        XCTAssertTrue(store.add(URL(fileURLWithPath: "/tmp/amg-b.png"), capturedAt: start.addingTimeInterval(1000)))
        XCTAssertEqual(store.batches.count, 2)
        let newest = try XCTUnwrap(store.batches.first)
        store.clear(batchID: newest.id)
        XCTAssertTrue(store.add(URL(fileURLWithPath: "/tmp/amg-c.png"), capturedAt: start.addingTimeInterval(1100)))
        XCTAssertEqual(store.batches.count, 2, "a new batch, not the old one")
        XCTAssertEqual(store.batches.first?.items.map(\.url.lastPathComponent), ["amg-c.png"])
        XCTAssertTrue(store.add(URL(fileURLWithPath: "/tmp/amg-d.png"), capturedAt: start.addingTimeInterval(1150)))
        XCTAssertEqual(store.batches.first?.items.count, 2, "and the ones after it join it as usual")
    }

    @MainActor
    func testTheCompactPlayerRowDraws() throws {
        let row = CompactPlayerRowContent(artwork: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!,
                                          title: "Nightcall", artist: "Kavinsky", progress: 0.34, isPlaying: true)
        let renderer = ImageRenderer(content: row.frame(width: 600).padding(8).background(Color.black).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.height, 72, accuracy: 1)
        if let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map({ URL(fileURLWithPath: $0) }),
           let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: folder.appendingPathComponent("compact-player.png"))
        }
    }

    @MainActor
    func testTheCompactPlayerHasTheVolumeButtonOnHover() throws {
        XCTAssertTrue(Defaults.Keys.showPlayerVolumeRow.defaultValue, "the volume button is on unless switched off")
        XCTAssertFalse(CompactPlayerRowContent.extrasShown(hovered: false, popoverOpen: false), "calm while the pointer is away")
        XCTAssertTrue(CompactPlayerRowContent.extrasShown(hovered: true, popoverOpen: false))
        XCTAssertTrue(CompactPlayerRowContent.extrasShown(hovered: false, popoverOpen: true), "stays while its slider is open")

        // A stand-in for the button: the real one reads the system volume.
        let row = CompactPlayerRowContent(artwork: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!,
                                          title: "Nightcall", artist: "Kavinsky", progress: 0.34, isPlaying: true,
                                          volumeControl: AnyView(Image(systemName: "speaker.wave.2.fill").frame(width: 28, height: 28)),
                                          showsExtras: true)
        let renderer = ImageRenderer(content: row.frame(width: 600).padding(8).background(Color.black).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.height, 72, accuracy: 1, "the button fits the one row")
        if let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map({ URL(fileURLWithPath: $0) }),
           let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: folder.appendingPathComponent("compact-player-volume.png"))
        }
    }

    // MARK: Temporary clipboard screenshots (owner's choice, 15.10)

    func testClipboardScreenshotsAreKeptOnlyInTheTemporaryFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-tempshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fresh = folder.appendingPathComponent("fresh.png")
        let old = folder.appendingPathComponent("old.png")
        try Data([1]).write(to: fresh)
        try Data([2]).write(to: old)
        try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-25 * 3600)], ofItemAtPath: old.path)

        XCTAssertTrue(TemporaryClipboardShots.isTemporary(fresh, in: folder))
        XCTAssertFalse(TemporaryClipboardShots.isTemporary(URL(fileURLWithPath: "/Users/x/Screenshots/a.png"), in: folder))
        XCTAssertTrue(TemporaryClipboardShots.removeExpired(in: folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "older than a day: gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("amg-outside-\(UUID().uuidString).png")
        try Data([3]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        TemporaryClipboardShots.remove([fresh, outside], in: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "never a file outside the folder")

        TemporaryClipboardShots.removeAll(in: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(TemporaryClipboardShots.folder.path.hasPrefix(FileManager.default.temporaryDirectory.path),
                      "the system's temporary folder, not ~/Screenshots")
    }

    func testATemporaryScreenshotIsKnownByItsPathAlone() {
        let folder = URL(fileURLWithPath: "/private/var/folders/xy/T/Skerry clipboard screenshots", isDirectory: true)
        XCTAssertTrue(TemporaryClipboardShots.holds(path: folder.path + "/Clipboard Screenshot 1.png", in: folder))
        XCTAssertFalse(TemporaryClipboardShots.holds(path: "/Users/someone/Desktop/Screenshot 1.png", in: folder))
        XCTAssertFalse(TemporaryClipboardShots.holds(path: folder.path + " 2/a.png", in: folder), "a neighbour folder")
        XCTAssertFalse(TemporaryClipboardShots.holds(path: folder.path, in: folder), "the folder itself")
    }

    func testRemovingATemporaryScreenshotDeletesItWithoutTheTrashQuestion() throws {
        let saved = Defaults[.screenshotMoveOriginalsToTrash]
        defer { Defaults[.screenshotMoveOriginalsToTrash] = saved }
        Defaults[.screenshotMoveOriginalsToTrash] = true
        let folder = TemporaryClipboardShots.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let shot = folder.appendingPathComponent("test-\(UUID().uuidString).png")
        try Data([1]).write(to: shot)
        defer { try? FileManager.default.removeItem(at: shot) }

        let manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))
        XCTAssertTrue(manager.store.add(shot, capturedAt: Date()))
        let batch = try XCTUnwrap(manager.store.batches.first)
        manager.requestClear(batch)
        XCTAssertNil(manager.pendingRemoval, "a temporary copy has no original to put in the Trash")
        XCTAssertTrue(manager.store.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shot.path), "and it is deleted at once")
    }

    // MARK: Full-screen clipboard screenshots (⌃⇧⌘3), found live on 15.10

    private func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testAFullScreenPictureCountsAsAScreenshotWithoutTheTool() {
        let savedTool = ClipboardScreenshotDetector.isScreenshotToolRunning
        let savedSizes = ClipboardScreenshotDetector.screenPixelSizes
        defer {
            ClipboardScreenshotDetector.isScreenshotToolRunning = savedTool
            ClipboardScreenshotDetector.screenPixelSizes = savedSizes
        }
        // ⌃⇧⌘3 starts no screenshot tool the app can see.
        ClipboardScreenshotDetector.isScreenshotToolRunning = { false }
        ClipboardScreenshotDetector.screenPixelSizes = { [CGSize(width: 8, height: 5)] }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.amidamaru940.skerry.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setData(png(width: 8, height: 5), forType: .png)
        XCTAssertEqual(ClipboardScreenshotDetector.pixelSize(of: pasteboard), CGSize(width: 8, height: 5))
        XCTAssertTrue(ClipboardScreenshotDetector.isScreenshot(pasteboard), "exactly one display: a screenshot")

        pasteboard.clearContents()
        pasteboard.setData(png(width: 9, height: 5), forType: .png)
        XCTAssertFalse(ClipboardScreenshotDetector.isScreenshot(pasteboard), "any other size: an ordinary picture")

        pasteboard.clearContents()
        pasteboard.setData(png(width: 8, height: 5), forType: .png)
        pasteboard.setString("caption", forType: .string)
        XCTAssertFalse(ClipboardScreenshotDetector.isScreenshot(pasteboard), "a picture with text is a copy, not a screenshot")
    }
}
