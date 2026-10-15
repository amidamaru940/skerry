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
import CoreGraphics
import Defaults
import XCTest

/// Step D2: opening from the ears, symmetric wings, the shelf flash, Keep
/// Awake in the closed island, Compact instead of the minimalistic mode.
final class ClosedIslandTests: XCTestCase {
    // A 1512 × 982 screen with a 200 × 32 notch in the middle.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private var notch: CGRect { IslandHoverZone.notchRect(screenFrame: screen, width: 200, height: 32) }

    // MARK: Hover ears

    func testTheNotchHangsFromTheTopEdgeInTheMiddle() {
        XCTAssertEqual(notch, CGRect(x: 656, y: 950, width: 200, height: 32))
        let shifted = IslandHoverZone.notchRect(screenFrame: screen, width: 200, height: 32, xOffset: 40)
        XCTAssertEqual(shifted.minX, 696)
    }

    func testThePointerOpensTheIslandFromAnEarBesideTheNotch() {
        let zone = IslandHoverZone.zone(around: notch)
        // In the menu bar 25 pt left of the notch and 25 pt right of it.
        XCTAssertTrue(IslandHoverZone.contains(zone, CGPoint(x: notch.minX - 25, y: 975)))
        XCTAssertTrue(IslandHoverZone.contains(zone, CGPoint(x: notch.maxX + 25, y: 975)))
        // Exactly at the ear's edge and on the top pixel still count.
        XCTAssertTrue(IslandHoverZone.contains(zone, CGPoint(x: notch.minX - 28, y: 982)))
        // Past the ear: an ordinary menu bar item.
        XCTAssertFalse(IslandHoverZone.contains(zone, CGPoint(x: notch.minX - 30, y: 975)))
        XCTAssertFalse(IslandHoverZone.contains(zone, CGPoint(x: notch.maxX + 30, y: 975)))
    }

    func testTheZoneReachesSixPointsBelowTheNotch() {
        let zone = IslandHoverZone.zone(around: notch)
        XCTAssertTrue(IslandHoverZone.contains(zone, CGPoint(x: notch.midX, y: notch.minY - 5)))
        XCTAssertFalse(IslandHoverZone.contains(zone, CGPoint(x: notch.midX, y: notch.minY - 7)))
    }

    func testAClickOpensOnlyOnTheIslandNotInAnEar() {
        let click = IslandHoverZone.clickArea(around: notch)
        XCTAssertTrue(IslandHoverZone.contains(click, CGPoint(x: notch.minX - 11, y: 975)), "upstream's 12 pt margin")
        XCTAssertFalse(IslandHoverZone.contains(click, CGPoint(x: notch.minX - 20, y: 975)), "the ear is the menu bar's")
        XCTAssertFalse(IslandHoverZone.clickOpens(onNotch: false, overIsland: false))
        XCTAssertTrue(IslandHoverZone.clickOpens(onNotch: true, overIsland: false))
        XCTAssertTrue(IslandHoverZone.clickOpens(onNotch: false, overIsland: true))
    }

    func testHoverStartsInTheZoneAndEndsOnlyOffTheZoneAndTheIsland() {
        XCTAssertEqual(IslandHoverZone.change(inZone: true, overIsland: false, isHovering: false), .enter)
        XCTAssertEqual(IslandHoverZone.change(inZone: true, overIsland: false, isHovering: true), .none)
        XCTAssertEqual(IslandHoverZone.change(inZone: false, overIsland: false, isHovering: true), .exit)
        XCTAssertEqual(IslandHoverZone.change(inZone: false, overIsland: false, isHovering: false), .none)
        // A wide music wing reaches past the ears: still hovering there.
        XCTAssertEqual(IslandHoverZone.change(inZone: false, overIsland: true, isHovering: true), .none)
    }

    // MARK: Symmetric wings

    func testTheLeftWingMatchesAWiderRightWing() {
        // Scrolling title: artwork wing ~20 pt, title wing ~151 pt.
        XCTAssertEqual(IslandWings.symmetricWidth(left: 20, right: 151), 151)
        XCTAssertEqual(IslandWings.symmetricWidth(left: 20, right: 20), 20)
        // The island's centre then sits on the camera.
        let left = IslandWings.symmetricWidth(left: 20, right: 151)
        let total = left + 200 + 151
        XCTAssertEqual(left + 100, total / 2)
    }

    // MARK: Shelf flash

    func testOnlyFilesNewSinceTheLastLookCount() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(ShelfFlashModel.added(previous: nil, current: [a, b]), 0, "the saved shelf at launch")
        XCTAssertEqual(ShelfFlashModel.added(previous: [a], current: [a, b, c]), 2)
        XCTAssertEqual(ShelfFlashModel.added(previous: [a, b], current: [a]), 0, "removing never flashes")
    }

    @MainActor
    func testAddingFilesFlashesForAMoment() {
        let model = ShelfFlashModel()
        let a = UUID(), b = UUID()
        model.itemsChanged([a])
        XCTAssertNil(model.flash, "loading the shelf does not flash")
        model.itemsChanged([a, b])
        XCTAssertEqual(model.flash?.added, 1)
        model.clear()
        XCTAssertNil(model.flash)
        model.itemsChanged([a])
        XCTAssertNil(model.flash)
        XCTAssertEqual(ShelfFlashModel.duration, 2.5)
    }

    // MARK: Keep Awake

    func testKeepAwakeIsVisibleInTheClosedIsland() {
        XCTAssertEqual(ClosedIndicator.defaultOrder.last, .keepAwake, "can stay on for hours: below the rest")
        XCTAssertTrue(ClosedIndicator.keepAwake.pairsWithMusic, "a cup on the artwork while music plays")
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: [.keepAwake], order: ClosedIndicator.defaultOrder), .keepAwake)
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: [.keepAwake, .shelf], order: ClosedIndicator.defaultOrder), .shelf)
        XCTAssertEqual(ClosedIndicatorResolver.musicBadge(active: [.music, .keepAwake], order: ClosedIndicator.defaultOrder), .keepAwake)
    }

    func testKeepAwakeShowsTimeLeftOrInfinityInEqualWings() {
        XCTAssertEqual(KeepAwakeLiveActivity.label(remaining: nil), "∞")
        XCTAssertEqual(KeepAwakeLiveActivity.label(remaining: 895), "14:55")
        XCTAssertEqual(KeepAwakeLiveActivity.wingWidth(for: "∞"), 26)
        XCTAssertGreaterThan(KeepAwakeLiveActivity.wingWidth(for: "1:02:03"), KeepAwakeLiveActivity.wingWidth(for: "14:55"))
    }

    // MARK: Compact instead of minimalistic

    func testCompactKeepsTheMainTabsAndTheirOrder() {
        let all = NotchTabLayout.visibleTabs(order: NotchTab.defaultOrder, hidden: [], layout: .compact) { _ in true }
        XCTAssertEqual(all, [.nowPlaying, .screenshots, .clipboard, .shelf])
        let reordered = NotchTabLayout.visibleTabs(order: [.terminal, .shelf, .nowPlaying], hidden: [.screenshots], layout: .compact) { _ in true }
        XCTAssertEqual(reordered, [.shelf, .nowPlaying, .clipboard])
        XCTAssertEqual(NotchTabLayout.visibleTabs(order: NotchTab.defaultOrder, hidden: [], layout: .standard) { _ in true },
                       NotchTab.defaultOrder)
    }

    func testCompactMakesNowPlayingOneLowerRow() {
        XCTAssertEqual(compactHomeHeight(for: .home, layout: .compact), 140)
        XCTAssertNil(compactHomeHeight(for: .home, layout: .standard))
        XCTAssertNil(compactHomeHeight(for: .clipboard, layout: .compact), "other tabs keep their height")
        XCTAssertEqual(CompactPlayerRowContent.progress(elapsed: 30, duration: 120), 0.25)
        XCTAssertEqual(CompactPlayerRowContent.progress(elapsed: 200, duration: 120), 1)
        XCTAssertNil(CompactPlayerRowContent.progress(elapsed: 10, duration: 0), "a live stream has no length")
    }

    func testTheMinimalisticModeBecomesCompactAndNeverHidesTheTabs() {
        XCTAssertEqual(IslandLayout.migratedFromMinimalistic(minimalistic: true, current: .standard), .compact)
        XCTAssertEqual(IslandLayout.migratedFromMinimalistic(minimalistic: false, current: .standard), .standard)
        XCTAssertEqual(IslandLayout.migratedFromMinimalistic(minimalistic: false, current: .compact), .compact)
        XCTAssertEqual(Defaults.Keys.islandLayout.defaultValue, .standard)
        XCTAssertTrue(IslandLayout.compact.keeps(.nowPlaying), "never an island without a tab")
    }
}
