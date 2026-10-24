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
import XCTest

/// The audit's minor items (15.10): Notes paste, tabs and the notch, the
/// screenshot grid, dragged thumbnails, the plug-in title.
final class MinorAuditTests: XCTestCase {

    func testNotesPasteGoesWhereTheCaretIs() {
        func action(file: Bool = false, image: Bool = false, text: Bool = false, focused: Bool = false, editor: Bool = false) -> NotesPaste {
            NotesPaste.action(hasImageFile: file, hasImageData: image, hasText: text, textFieldFocused: focused, inEditor: editor)
        }
        XCTAssertEqual(action(text: true, focused: true, editor: true), .intoFocusedField,
                       "title or note with the caret: pasted there, not appended to the end")
        XCTAssertEqual(action(text: true, focused: true), .intoFocusedField, "the search field pastes too, no new note")
        XCTAssertEqual(action(image: true, text: true, focused: true), .intoFocusedField,
                       "text that comes with a picture of itself is text in a field")
        XCTAssertEqual(action(file: true, text: true, focused: true), .imageFile, "an image file still attaches")
        XCTAssertEqual(action(image: true, focused: true), .imageData, "a picture alone attaches")
        XCTAssertEqual(action(text: true, editor: true), .appendToNote, "no field focused: as before")
        XCTAssertEqual(action(text: true), .newNote)
        XCTAssertEqual(action(), .nothing)
    }

    func testTheTabsNeverRunUnderTheNotch() {
        XCTAssertEqual(recommendedMinimumNotchWidth(forTabCount: 4, notchWidth: 200), 640, "upstream's steps stay the floor")
        XCTAssertEqual(recommendedMinimumNotchWidth(forTabCount: 6, notchWidth: 200), 770)
        XCTAssertEqual(recommendedMinimumNotchWidth(forTabCount: 7, notchWidth: 200), 794, "seven used to slide under the camera")
        XCTAssertEqual(recommendedMinimumNotchWidth(forTabCount: 8, notchWidth: 200), 870)
        for notch in [CGFloat(185), 200, 240] {
            for count in 1...10 {
                let width = recommendedMinimumNotchWidth(forTabCount: count, notchWidth: notch)
                // The tabs get half of what the notch leaves, less the header's insets.
                let room = (width - 60 - notch) / 2
                XCTAssertGreaterThanOrEqual(room, CGFloat(count) * tabButtonPitch - 4, "\(count) tabs beside a \(notch) pt notch")
            }
        }
    }

    func testTheScreenshotGridFillsItsWidth() {
        let grid = ScreenshotGridLayout.columns(width: 480, minimumTile: 110)
        XCTAssertEqual(grid.count, 4)
        XCTAssertEqual(grid.tile, 113, "stretched from 110 to share the row (Buffer v3: the 9 pt film gap)")
        for width in stride(from: CGFloat(200), through: 900, by: 37) {
            for minimum in [CGFloat(70), 110, 200] {
                let g = ScreenshotGridLayout.columns(width: width, minimumTile: minimum)
                let used = CGFloat(g.count) * g.tile + ScreenshotGridLayout.spacing * CGFloat(g.count - 1)
                XCTAssertLessThanOrEqual(used, width)
                XCTAssertGreaterThan(used, width - CGFloat(g.count), "no tile-sized gap on the right")
                if width >= minimum { XCTAssertGreaterThanOrEqual(g.tile, minimum, "never smaller than chosen") }
            }
        }
        XCTAssertEqual(ScreenshotGridLayout.columns(width: 0, minimumTile: 110).count, 1, "before the width is known")
    }

    func testEachDraggedScreenshotShowsItsOwnPicture() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-drag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func png(_ name: String, width: Int, height: Int) throws -> URL {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            let url = folder.appendingPathComponent(name)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
            return url
        }
        let wide = try png("wide.png", width: 800, height: 400)
        let tall = try png("tall.png", width: 300, height: 600)
        let grabbed = NSImage(size: NSSize(width: 10, height: 10))

        XCTAssertTrue(ScreenshotDragSourceView.dragImage(for: wide, index: 0, count: 1, grabbed: grabbed) === grabbed,
                      "one file: the tile that was grabbed")
        let first = ScreenshotDragSourceView.dragImage(for: wide, index: 0, count: 2, grabbed: grabbed)
        let second = ScreenshotDragSourceView.dragImage(for: tall, index: 1, count: 2, grabbed: grabbed)
        XCTAssertFalse(first === grabbed, "several: each its own, not the grabbed one")
        XCTAssertEqual(first.size, NSSize(width: 128, height: 64), "a small thumbnail of that file")
        XCTAssertEqual(second.size, NSSize(width: 64, height: 128))
        let late = ScreenshotDragSourceView.dragImage(for: tall, index: ScreenshotDragSourceView.dragThumbnailLimit, count: 9, grabbed: grabbed)
        XCTAssertNotEqual(late.size, NSSize(width: 64, height: 128), "past the first few: the file icon, no decode")
    }

    func testTheKeyCatcherNeverTakesAClick() {
        // It lies under the screenshot grid; a click there belongs to the tile.
        let catcher = IslandKeyCatcher.KeyCatcherView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertNil(catcher.hitTest(NSPoint(x: 200, y: 150)))
        XCTAssertTrue(catcher.acceptsFirstResponder, "it still takes the keys")
    }

    func testPluggingInWhenFullDoesNotSayCharging() {
        XCTAssertEqual(BatteryTemporaryActivityView.compactTitle(for: .charging, batteryLevel: 100), String(localized: "Fully charged"))
        XCTAssertEqual(BatteryTemporaryActivityView.compactTitle(for: .charging, batteryLevel: 64), String(localized: "Charging"))
        XCTAssertEqual(BatteryTemporaryActivityView.compactTitle(for: .lowBattery, batteryLevel: 10), String(localized: "Low Battery"))
    }
}
