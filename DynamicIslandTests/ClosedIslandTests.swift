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
import CoreGraphics
import Defaults
import XCTest

/// Step D2: the click area (the hover ears were removed for energy),
/// symmetric wings, the shelf flash, Keep Awake in the closed island,
/// Compact instead of the minimalistic mode.
final class ClosedIslandTests: XCTestCase {
    // A 1512 × 982 screen with a 200 × 32 notch in the middle.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private var notch: CGRect { IslandHoverZone.notchRect(screenFrame: screen, width: 200, height: 32) }

    // MARK: Hover and click area

    func testTheNotchHangsFromTheTopEdgeInTheMiddle() {
        XCTAssertEqual(notch, CGRect(x: 656, y: 950, width: 200, height: 32))
        let shifted = IslandHoverZone.notchRect(screenFrame: screen, width: 200, height: 32, xOffset: 40)
        XCTAssertEqual(shifted.minX, 696)
    }

    func testTheClickAreaReachesSixPointsBelowTheNotch() {
        let click = IslandHoverZone.clickArea(around: notch)
        XCTAssertTrue(IslandHoverZone.contains(click, CGPoint(x: notch.midX, y: notch.minY - 5)))
        XCTAssertFalse(IslandHoverZone.contains(click, CGPoint(x: notch.midX, y: notch.minY - 7)))
    }

    func testAClickOpensOnlyOnTheIslandNotBesideIt() {
        let click = IslandHoverZone.clickArea(around: notch)
        XCTAssertTrue(IslandHoverZone.contains(click, CGPoint(x: notch.minX, y: 975)), "the island's edge")
        XCTAssertTrue(IslandHoverZone.contains(click, CGPoint(x: notch.maxX, y: 975)), "the island's edge")
        // A menu title flush against the camera is the menu bar's: upstream's
        // 12 pt margin beside the notch is gone.
        XCTAssertFalse(IslandHoverZone.contains(click, CGPoint(x: notch.minX - 1, y: 975)), "the menu bar's")
        XCTAssertFalse(IslandHoverZone.contains(click, CGPoint(x: notch.minX - 11, y: 975)), "the menu bar's")
        XCTAssertFalse(IslandHoverZone.contains(click, CGPoint(x: notch.maxX + 11, y: 975)), "the menu bar's")
        // Below the notch, where there is no menu, the strip stays.
        XCTAssertEqual(click, CGRect(x: notch.minX, y: notch.minY - IslandHoverZone.below, width: notch.width, height: notch.height + IslandHoverZone.below))
        XCTAssertFalse(IslandHoverZone.clickOpens(onNotch: false, overIsland: false))
        XCTAssertTrue(IslandHoverZone.clickOpens(onNotch: true, overIsland: false))
        XCTAssertTrue(IslandHoverZone.clickOpens(onNotch: false, overIsland: true))
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

    // MARK: Nothing behind the camera

    /// Every closed state with text, at the longest strings it shows, on a
    /// 185 pt notch (14" MacBook Pro) and a 200 pt one: the trailing content
    /// starts at or past the camera's right edge, and the leading content
    /// ends at or before its left edge (E §2.1).
    func testNoClosedTextSitsBehindTheCamera() {
        for notch: CGFloat in [185, 200] {
            var states: [(String, ClosedWingGeometry)] = []

            // Focus (S29): the owner's «Не беспокоить», a custom name past the cap, the toast.
            for label in ["Не беспокоить", "Do Not Disturb", "Фокус выключен", "Работа над очень длинным проектом", "On"] {
                states.append(("Focus «\(label)»", DoNotDisturbLiveActivity.closedGeometry(closedNotchWidth: notch, showsGlyph: true, label: label)))
            }
            states.append(("Focus, glyph only", DoNotDisturbLiveActivity.closedGeometry(closedNotchWidth: notch, showsGlyph: true, label: nil)))

            // Caps Lock, AirPods and the other text HUDs.
            func hud(
                _ type: SneakContentType,
                listening: String? = nil,
                battery: Bool = false,
                deviceName: Bool = false,
                percentage: Bool = false,
                capsLabel: Bool = true
            ) -> ClosedWingGeometry {
                let wings = InlineHUD.textWings(
                    type: type,
                    listeningModeLabel: listening,
                    hasBatteryLevel: battery,
                    showsDeviceName: deviceName,
                    circularBattery: false,
                    showsBatteryPercentage: percentage,
                    showsCapsLockLabel: capsLabel,
                    gestureProgress: 0
                )
                return .equalWings(closedNotchWidth: notch, leading: wings.info, trailing: wings.trailing)
            }
            states.append(("Caps Lock", hud(.capsLock)))
            states.append(("Caps Lock, glyph only", hud(.capsLock, capsLabel: false)))
            for mode in ["Распознавание разговора", "Conversation Awareness", "Шумоподавление"] {
                states.append(("AirPods «\(mode)»", hud(.bluetoothAudio, listening: mode)))
            }
            states.append(("AirPods name and battery", hud(.bluetoothAudio, battery: true, deviceName: true, percentage: true)))
            states.append(("AirPods battery", hud(.bluetoothAudio, battery: true, percentage: true)))

            // Battery (S14–S16).
            for title in ["Полный заряд", "Низкий заряд", "Полностью заряжена", "Fully charged"] {
                states.append(("Battery «\(title)»", BatteryTemporaryActivityView.compactGeometry(title: title, closedNotchWidth: notch)))
            }

            // Keep Awake (S23–S24), colour copied (S27), screenshot flash (S17).
            for label in ["∞", "14:55", "1:02:03"] {
                states.append(("Keep Awake «\(label)»", KeepAwakeLiveActivity.closedGeometry(closedNotchWidth: notch, label: label)))
            }
            states.append(("Colour copied", ColorPickedLiveActivityContent.closedGeometry(closedNotchWidth: notch, hex: "#5BBEEB")))
            for count in [1, 3, 25, 99] {
                states.append(("Screenshot flash \(count)", ClosedScreenshotFlash.closedGeometry(closedNotchWidth: notch, count: count)))
            }

            // Timer (S8–S10): a long name in the leading wing, an hour on the clock.
            let name = min(max(ClosedWingE.measure("Очень длинное название таймера", font: .systemFont(ofSize: 12, weight: .medium)), 44), 220)
            let countdown = ClosedWingE.measure("1:00:00", font: .monospacedSystemFont(ofSize: 13, weight: .semibold))
            states.append(("Timer", TimerLiveActivity.closedGeometry(
                closedNotchWidth: notch,
                middle: notch,
                leftWing: 28 + 11 + 8 + name + 18,
                rightWing: 22 + max(countdown + 16, 72)
            )))

            // Reminder (S33): «in 120 min» beside the 26 pt glyph.
            let minutes = ClosedWingE.measure("in 120 min", font: .systemFont(ofSize: 13, weight: .semibold))
            states.append(("Reminder", ReminderLiveActivity.closedGeometry(closedNotchWidth: notch, leftWing: 16 + 26, rightWing: 16 + max(minutes + 18, 88))))

            // Recording (S26): an hour, and «Ошибка», scaled into their wing.
            for text in ["1:02:03", "Ошибка"] {
                let width = ClosedWingE.measure(text, font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold))
                states.append(("Recording «\(text)»", RecordingLiveActivity.closedGeometry(
                    closedNotchWidth: notch,
                    hudWidth: notch + RecordingHUDPresentation.compact.extraWidth,
                    centerWidth: notch,
                    textWidth: width
                )))
            }

            // Download (S34) with its rate, and an extension's widest value.
            states.append(("Download", DownloadLiveActivity.closedGeometry(
                closedNotchWidth: notch,
                notchHeight: 32,
                isHovering: false,
                gestureProgress: 0,
                isDownloading: true,
                speedText: "1023.5 MB/s"
            )))
            let extensionValue = 44 + notch * 0.6
            let layout = ExtensionStandaloneLayout.equalWings(
                outerHeight: 32,
                contentHeight: 20,
                leadingContentWidth: 44,
                centerWidth: notch,
                trailingContentWidth: extensionValue
            )
            states.append(("Extension", layout.closedGeometry(closedNotchWidth: notch, trailingContent: extensionValue)))

            for (state, geometry) in states {
                if geometry.trailingContent > 0 {
                    XCTAssertGreaterThanOrEqual(
                        geometry.trailingContentMinX, geometry.cameraMaxX,
                        "\(state), notch \(notch): the trailing content starts under the camera"
                    )
                }
                XCTAssertTrue(geometry.clearsCamera, "\(state), notch \(notch)")
            }
        }

        // The row the owner saw (22.10): a 20 pt glyph wing beside a 164 pt
        // name wing slid «Не беспокоить» in to 26 pt right of the camera's centre.
        let before = ClosedWingGeometry(leadingWing: 20, middle: 185, trailingWing: 164, leadingContent: 20, trailingContent: 160, camera: 181)
        XCTAssertLessThan(before.trailingContentMinX, before.cameraMaxX)
        XCTAssertFalse(before.clearsCamera)
        // Now: both wings 98, the name from 92.5, past the camera's 90.5.
        let focus = DoNotDisturbLiveActivity.closedGeometry(closedNotchWidth: 185, showsGlyph: true, label: "Не беспокоить")
        XCTAssertEqual(focus.leadingWing, focus.trailingWing)
        XCTAssertGreaterThanOrEqual(focus.trailingContentMinX, 92.5)
        XCTAssertLessThanOrEqual(DoNotDisturbLiveActivity.labelWidth("Работа над очень длинным проектом и ещё немного"), ClosedWingE.textCap)
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
