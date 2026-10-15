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

/// Step D5: Keep Awake, the one timer, popovers of one width.
@MainActor
final class PanelsTests: XCTestCase {
    // MARK: Keep Awake

    func testKeepAwakeSaysWhatIsGoingOn() {
        let off = KeepAwakeStatus.title(isActive: false, remaining: nil)
        let forever = KeepAwakeStatus.title(isActive: true, remaining: nil)
        let timed = KeepAwakeStatus.title(isActive: true, remaining: 895)
        XCTAssertNotEqual(off, forever)
        XCTAssertTrue(timed.contains("14:55"), timed)
        XCTAssertFalse(forever.contains("14:55"))
    }

    func testChoosingTheRunningDurationDoesNotRestartIt() {
        XCTAssertFalse(KeepAwakeStatus.shouldStart(.oneHour, isActive: true, active: .oneHour))
        XCTAssertTrue(KeepAwakeStatus.shouldStart(.twoHours, isActive: true, active: .oneHour))
        XCTAssertTrue(KeepAwakeStatus.shouldStart(.oneHour, isActive: false, active: nil))
    }

    func testDurationsFitOneRowShortestFirst() {
        let order = CaffeinateDuration.panelOrder
        XCTAssertEqual(order.count, 5, "one row that fits 280 pt")
        XCTAssertEqual(Set(order).union([.fourHours]), Set(CaffeinateDuration.allCases), "four hours stays in Settings")
        XCTAssertEqual(order.first, .fifteenMinutes)
        XCTAssertEqual(order.last, .indefinite)
        XCTAssertEqual(CaffeinateDuration.indefinite.shortName, "∞")
        for duration in order {
            XCTAssertLessThanOrEqual(duration.shortName.count, 7, duration.shortName)
        }
    }

    func testEveryPopoverHasOneWidth() {
        XCTAssertEqual(DS.panelWidth, 280)
    }

    // MARK: Timer

    func testTheTimerShowsThreePresetsWithShortLabels() {
        XCTAssertEqual(TimerTabLayout.presetCount, 3)
        XCTAssertTrue(TimerTabLayout.presetLabel(300).contains("5"))
        XCTAssertTrue(TimerTabLayout.presetLabel(5400).contains("1"))
        XCTAssertTrue(TimerTabLayout.presetLabel(5400).contains("30"))
        XCTAssertTrue(TimerTabLayout.presetLabel(45).contains("45"))
    }

    func testTheTimerPopoverBecomesTheTab() {
        let saved = Defaults[.timerDisplayMode]
        defer { Defaults[.timerDisplayMode] = saved }
        Defaults[.timerDisplayMode] = .popover
        Defaults.Keys.migrateTimerPopoverToTab()
        XCTAssertEqual(Defaults[.timerDisplayMode], .tab)
        Defaults.Keys.migrateTimerPopoverToTab()
        XCTAssertEqual(Defaults[.timerDisplayMode], .tab)
    }

    // MARK: Drawing

    func testTheKeepAwakePanelDraws() throws {
        let renderer = ImageRenderer(content: CaffeinatePopover().background(DS.Palette.surface).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, DS.panelWidth, accuracy: 1)
        if let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map({ URL(fileURLWithPath: $0) }),
           let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: folder.appendingPathComponent("keep-awake.png"))
        }
    }
}
