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
import SwiftUI
import XCTest

/// Step D1: design system and the new island header.
final class IslandHeaderTests: XCTestCase {
    // MARK: "New" dots instead of counts

    func testATabShowsADotOnlyForItemsThatAppearedSinceItWasLastSeen() {
        let tracker = TabNewItemsTracker()
        // First look (the island shown for the first time): nothing is new.
        XCTAssertFalse(tracker.hasNew(.clipboard, current: ["a", "b"]))
        // A new copy arrives.
        XCTAssertTrue(tracker.hasNew(.clipboard, current: ["a", "b", "c"]))
        // The tab is opened: seen.
        tracker.markSeen(.clipboard, current: ["a", "b", "c"])
        XCTAssertFalse(tracker.hasNew(.clipboard, current: ["a", "b", "c"]))
        // Removing items never brings the dot back.
        XCTAssertFalse(tracker.hasNew(.clipboard, current: ["a"]))
        // Tabs are tracked separately.
        XCTAssertFalse(tracker.hasNew(.shelf, current: ["x"]))
        XCTAssertTrue(tracker.hasNew(.shelf, current: ["x", "y"]))
    }

    func testMarkingSeenRedrawsOnlyWhenSomethingChanged() {
        let tracker = TabNewItemsTracker()
        tracker.markSeen(.screenshots, current: ["1"])
        let revision = tracker.revision
        tracker.markSeen(.screenshots, current: ["1"])
        XCTAssertEqual(tracker.revision, revision)
        tracker.markSeen(.screenshots, current: ["1", "2"])
        XCTAssertEqual(tracker.revision, revision + 1)
    }

    func testTheNewRuleItself() {
        XCTAssertFalse(TabNewItemsTracker.hasNew(current: ["a"], seen: nil))
        XCTAssertFalse(TabNewItemsTracker.hasNew(current: [], seen: ["a"]))
        XCTAssertTrue(TabNewItemsTracker.hasNew(current: ["b"], seen: ["a"]))
    }

    // MARK: Status capsule

    func testTheCapsuleIsEmptyWhenNothingIsGoingOn() {
        XCTAssertEqual(IslandStatus.items(recording: false, keepAwake: false, keepAwakeRemaining: nil,
                                          focus: false, batteryPercent: 80, charging: false), [])
    }

    func testTheCapsuleShowsLiveStatesInOrder() {
        let items = IslandStatus.items(recording: true, keepAwake: true, keepAwakeRemaining: 895,
                                       focus: true, batteryPercent: 15, charging: false)
        XCTAssertEqual(items, [.recording, .keepAwake(remaining: 895), .focus, .lowBattery(percent: 15)])
    }

    func testBatteryShowsOnlyWhenLowAndNotCharging() {
        func battery(_ percent: Float?, charging: Bool = false) -> [IslandStatus.Item] {
            IslandStatus.items(recording: false, keepAwake: false, keepAwakeRemaining: nil,
                               focus: false, batteryPercent: percent, charging: charging)
        }
        XCTAssertEqual(battery(20), [.lowBattery(percent: 20)])
        XCTAssertEqual(battery(21), [])
        XCTAssertEqual(battery(10, charging: true), [])
        XCTAssertEqual(battery(nil), [])   // battery indicator turned off
        XCTAssertEqual(IslandStatus.items(recording: false, keepAwake: true, keepAwakeRemaining: nil,
                                          focus: false, batteryPercent: nil, charging: false),
                       [.keepAwake(remaining: nil)])
    }

    // MARK: "…" menu

    func testTheMenuReplacesTheOldHeaderButtons() {
        let defaults = IslandMoreMenu.entries(for: .init())
        XCTAssertEqual(defaults, [.keepAwake, .colorPicker, .clipboardPause(paused: false), .settings])

        var all = IslandMoreMenu.Features()
        all.clipboardOutsideTabs = true
        all.clipboardPaused = true
        all.appVolume = true
        all.mirror = true
        XCTAssertEqual(IslandMoreMenu.entries(for: all),
                       [.keepAwake, .colorPicker, .clipboard, .clipboardPause(paused: true), .appVolume, .mirror, .settings])

        let nothing = IslandMoreMenu.Features(keepAwake: false, colorPicker: false, clipboard: false)
        XCTAssertEqual(IslandMoreMenu.entries(for: nothing), [.settings])
    }

    func testOnTheBufferTheMenuClearsTheHistory() {
        // Buffer v3 (Q26): the tab's own «…» is gone; «Очистить историю» heads
        // the island's menu on «Буфер», a hairline under it, no question.
        var buffer = IslandMoreMenu.Features()
        buffer.clipboardHistoryCount = 14
        let entries = IslandMoreMenu.entries(for: buffer)
        XCTAssertEqual(entries, [.clearClipboardHistory(count: 14), .keepAwake, .colorPicker, .clipboardPause(paused: false), .settings])
        XCTAssertTrue(IslandMoreMenu.startsSection(entries, at: 1), "a hairline under «Очистить историю»")
        XCTAssertFalse(IslandMoreMenu.startsSection(entries, at: 2))
        XCTAssertTrue(IslandMoreMenu.startsSection(entries, at: entries.count - 1), "and above Settings")
        XCTAssertNil(IslandMoreMenu.panel(for: .clearClipboardHistory(count: 14)), "it acts at once")

        var off = buffer
        off.clipboard = false
        XCTAssertFalse(IslandMoreMenu.entries(for: off).contains(.clearClipboardHistory(count: 14)), "no clipboard, nothing to clear")
    }

    func testEntriesOpenTheirPanelInPlaceOrActAtOnce() {
        XCTAssertEqual(IslandMoreMenu.panel(for: .keepAwake), .keepAwake)
        XCTAssertEqual(IslandMoreMenu.panel(for: .colorPicker), .colorPicker)
        XCTAssertEqual(IslandMoreMenu.panel(for: .clipboard), .clipboard)
        XCTAssertEqual(IslandMoreMenu.panel(for: .appVolume), .appVolume)
        XCTAssertNil(IslandMoreMenu.panel(for: .clipboardPause(paused: false)))
        XCTAssertNil(IslandMoreMenu.panel(for: .mirror))
        XCTAssertNil(IslandMoreMenu.panel(for: .settings))
    }

    // MARK: Design system

    private func rgb(_ color: Color) -> (Int, Int, Int) {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (Int((ns.redComponent * 255).rounded()), Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }

    func testThePaletteMatchesTheApprovedDesign() {
        XCTAssertTrue(rgb(DS.Palette.accent) == (0x0A, 0x84, 0xFF), "Apple blue accent")
        XCTAssertTrue(rgb(DS.Palette.text) == (0xF5, 0xF5, 0xF7))
        XCTAssertTrue(rgb(DS.Palette.textTertiary) == (0x8E, 0x8E, 0x93))
        XCTAssertEqual(DS.iconSize, 15)
        XCTAssertEqual(DS.hitTarget, 28)
        XCTAssertEqual([DS.Radius.chip, DS.Radius.card, DS.Radius.panel], [6, 10, 14])
    }

    /// Small text must stay readable on the black island (WCAG 4.5:1).
    func testTertiaryTextIsReadableOnBlack() {
        func luminance(_ c: (Int, Int, Int)) -> Double {
            func channel(_ v: Int) -> Double {
                let s = Double(v) / 255
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
        }
        let contrast = (luminance(rgb(DS.Palette.textTertiary)) + 0.05) / 0.05
        XCTAssertGreaterThanOrEqual(contrast, 4.5)
    }
}
