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
import Defaults
import XCTest

final class NotchTabLayoutTests: XCTestCase {
    func testDefaultOrderPutsTheFourMainTabsFirst() {
        XCTAssertEqual(Array(NotchTab.defaultOrder.prefix(4)), [.nowPlaying, .screenshots, .clipboard, .shelf])
        XCTAssertEqual(Set(NotchTab.defaultOrder), Set(NotchTab.allCases))
    }

    func testNormalizedOrderDropsDuplicatesAndAppendsNewTabs() {
        let stored: [NotchTab] = [.shelf, .clipboard, .shelf, .nowPlaying]
        let order = NotchTabLayout.normalizedOrder(stored)

        XCTAssertEqual(Array(order.prefix(3)), [.shelf, .clipboard, .nowPlaying])
        XCTAssertEqual(order.count, NotchTab.allCases.count)
        XCTAssertEqual(Set(order), Set(NotchTab.allCases))
    }

    func testVisibleTabsSkipHiddenAndUnavailableAndKeepTheOrder() {
        let order: [NotchTab] = [.clipboard, .nowPlaying, .shelf, .screenshots, .timer]
        let visible = NotchTabLayout.visibleTabs(
            order: order,
            hidden: [.shelf],
            isAvailable: { $0 != .timer && $0 != .stats && $0 != .notes && $0 != .terminal && $0 != .llmUsage }
        )
        XCTAssertEqual(visible, [.clipboard, .nowPlaying, .screenshots])
    }

    func testMoveDropsATabOntoAnother() {
        let order: [NotchTab] = [.nowPlaying, .screenshots, .clipboard, .shelf]
        XCTAssertEqual(Array(NotchTabLayout.move(.shelf, onto: .nowPlaying, in: order).prefix(4)),
                       [.shelf, .nowPlaying, .screenshots, .clipboard])
        XCTAssertEqual(Array(NotchTabLayout.move(.nowPlaying, onto: .clipboard, in: order).prefix(4)),
                       [.screenshots, .clipboard, .nowPlaying, .shelf])
        XCTAssertEqual(Array(NotchTabLayout.move(.clipboard, onto: .clipboard, in: order).prefix(4)), order)
    }

    func testIslandReopensOnTheLastTabByDefault() {
        let visible: [NotchTab] = [.nowPlaying, .screenshots, .clipboard]
        XCTAssertEqual(NotchTabLayout.viewAfterClose(current: .clipboard, defaultTab: nil, visible: visible), .clipboard)
        XCTAssertEqual(NotchTabLayout.viewAfterClose(current: .clipboard, defaultTab: .screenshots, visible: visible), .screenshots)
        XCTAssertEqual(NotchTabLayout.viewAfterClose(current: .clipboard, defaultTab: .shelf, visible: visible), .home,
                       "a hidden default falls back to the first visible tab")
        XCTAssertEqual(NotchTabLayout.viewAfterClose(current: .clipboard, defaultTab: .shelf, visible: []), .home)
    }

    func testShelfOpensForFileDragsButNotWhileDraggingOutOfTheIsland() {
        XCTAssertTrue(NotchTabLayout.shouldOpenShelfOnFileDrag(enabled: false, shelfVisible: true, notchClosed: true, draggingOutOfIsland: false))
        XCTAssertTrue(NotchTabLayout.shouldOpenShelfOnFileDrag(enabled: true, shelfVisible: true, notchClosed: false, draggingOutOfIsland: false))
        XCTAssertFalse(NotchTabLayout.shouldOpenShelfOnFileDrag(enabled: false, shelfVisible: true, notchClosed: false, draggingOutOfIsland: false))
        XCTAssertFalse(NotchTabLayout.shouldOpenShelfOnFileDrag(enabled: true, shelfVisible: true, notchClosed: false, draggingOutOfIsland: true))
        XCTAssertFalse(NotchTabLayout.shouldOpenShelfOnFileDrag(enabled: true, shelfVisible: false, notchClosed: true, draggingOutOfIsland: false))
    }

    func testEveryTabMapsToItsViewAndBack() {
        for tab in NotchTab.allCases {
            XCTAssertEqual(NotchTab(view: tab.view), tab)
        }
        XCTAssertNil(NotchTab(view: .extensionExperience))
    }

    @MainActor
    func testGridTabsAreTallerAndTheTabCountUsesTheLayout() {
        XCTAssertEqual(tabOpenHeight(for: .screenshots), 320)
        XCTAssertEqual(tabOpenHeight(for: .clipboard), 320, "full height until its content is measured")
        XCTAssertNil(tabOpenHeight(for: .home))
        XCTAssertEqual(enabledStandardTabCount(), NotchTabLayout.visibleTabs.count)
    }

    func testLayoutDefaults() {
        XCTAssertEqual(Defaults.Keys.notchTabOrder.defaultValue, NotchTab.defaultOrder)
        // Decision 3 of the design plan: three tabs (and Terminal when it is on).
        XCTAssertEqual(Defaults.Keys.notchHiddenTabs.defaultValue, [.timer, .notes, .stats, .llmUsage])
        XCTAssertNil(Defaults.Keys.defaultNotchTab.defaultValue, "nil = last opened tab")
        XCTAssertTrue(Defaults.Keys.openScreenshotsOnNewScreenshot.defaultValue)
        XCTAssertTrue(Defaults.Keys.openShelfOnFileDrag.defaultValue)
        XCTAssertFalse(Defaults.Keys.openShelfByDefault.defaultValue)
    }
}

/// Uses the real settings store; every key touched is restored.
@MainActor
final class NotchTabLayoutPersistenceTests: XCTestCase {
    private var savedOrder: [NotchTab] = []
    private var savedHidden: [NotchTab] = []
    private var savedDefault: NotchTab?
    private var savedAutoOpen = true
    private var savedShelfEnabled = true
    private var savedView: NotchViews = .home

    override func setUp() {
        super.setUp()
        savedOrder = Defaults[.notchTabOrder]
        savedHidden = Defaults[.notchHiddenTabs]
        savedDefault = Defaults[.defaultNotchTab]
        savedAutoOpen = Defaults[.openScreenshotsOnNewScreenshot]
        savedShelfEnabled = Defaults[.enableScreenshotShelf]
        savedView = DynamicIslandViewCoordinator.shared.currentView
    }

    override func tearDown() {
        Defaults[.notchTabOrder] = savedOrder
        Defaults[.notchHiddenTabs] = savedHidden
        Defaults[.defaultNotchTab] = savedDefault
        Defaults[.openScreenshotsOnNewScreenshot] = savedAutoOpen
        Defaults[.enableScreenshotShelf] = savedShelfEnabled
        DynamicIslandViewCoordinator.shared.currentView = savedView
        super.tearDown()
    }

    func testOrderVisibilityAndDefaultTabAreSavedAndRestored() {
        let order: [NotchTab] = [.shelf, .clipboard, .screenshots, .nowPlaying]
        Defaults[.notchTabOrder] = order
        Defaults[.notchHiddenTabs] = [.clipboard]
        Defaults[.defaultNotchTab] = .screenshots

        // Read back through the stored representation.
        XCTAssertEqual(Defaults[.notchTabOrder], order)
        XCTAssertEqual(Defaults[.notchHiddenTabs], [.clipboard])
        XCTAssertEqual(Defaults[.defaultNotchTab], .screenshots)
        XCTAssertFalse(NotchTabLayout.visibleTabs.contains(.clipboard))
        XCTAssertEqual(NotchTabLayout.normalizedOrder(Defaults[.notchTabOrder]).first, .shelf)

        Defaults[.defaultNotchTab] = nil
        XCTAssertNil(Defaults[.defaultNotchTab])
    }

    /// Screenshots are part of the Clipboard tab since step D4.
    func testANewScreenshotOpensTheScreenshotsTab() throws {
        Defaults[.enableScreenshotShelf] = true
        Defaults[.notchHiddenTabs] = []
        Defaults[.openScreenshotsOnNewScreenshot] = true
        DynamicIslandViewCoordinator.shared.currentView = .home

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-autoopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shot = folder.appendingPathComponent("shot.png")
        try Data([1]).write(to: shot)

        let manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))
        manager.didCapture(shot, at: Date())
        XCTAssertEqual(DynamicIslandViewCoordinator.shared.currentView, .clipboard)
    }

    func testNoAutoOpenWhenTurnedOffOrTabHidden() throws {
        Defaults[.enableScreenshotShelf] = true
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-noautoopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))

        Defaults[.openScreenshotsOnNewScreenshot] = false
        DynamicIslandViewCoordinator.shared.currentView = .home
        let first = folder.appendingPathComponent("a.png")
        try Data([1]).write(to: first)
        manager.didCapture(first, at: Date())
        XCTAssertEqual(DynamicIslandViewCoordinator.shared.currentView, .home)

        Defaults[.openScreenshotsOnNewScreenshot] = true
        Defaults[.notchHiddenTabs] = [.clipboard]   // the tab the screenshots are in
        let second = folder.appendingPathComponent("b.png")
        try Data([2]).write(to: second)
        manager.didCapture(second, at: Date())
        XCTAssertEqual(DynamicIslandViewCoordinator.shared.currentView, .home)
    }
}
