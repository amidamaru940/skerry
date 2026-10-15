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
import Combine
import Defaults
import XCTest

/// Hiding private content while the screen is shared or recorded. Uses its
/// own ScreenPresentation instances fed by test subjects, never the real
/// screen-capture state.
final class ScreenPresentationTests: XCTestCase {
    func testDefaults() {
        XCTAssertTrue(Defaults.Keys.hideContentWhilePresenting.defaultValue)
        XCTAssertEqual(Defaults.Keys.hideNotchOption.defaultValue, .nowPlayingOnly)
    }

    func testContentIsHiddenOnlyWhileCapturingWithTheSettingOn() {
        XCTAssertTrue(ScreenPresentation.hidesContent(setting: true, capturing: true))
        XCTAssertFalse(ScreenPresentation.hidesContent(setting: true, capturing: false))
        XCTAssertFalse(ScreenPresentation.hidesContent(setting: false, capturing: true))
    }

    func testOnlySystemHUDsShowWhileHiding() {
        let allowed: [SneakContentType] = [.volume, .brightness, .backlight, .mic, .capsLock]
        let blocked: [SneakContentType] = [.music, .battery, .download, .timer, .reminder, .recording, .doNotDisturb,
                                           .bluetoothAudio, .privacy, .lockScreen,
                                           .extensionLiveActivity(bundleID: "a", activityID: "b")]
        for type in allowed {
            XCTAssertTrue(ScreenPresentation.allowsSneakPeek(type, hidingContent: true), "\(type)")
        }
        for type in blocked {
            XCTAssertFalse(ScreenPresentation.allowsSneakPeek(type, hidingContent: true), "\(type)")
            XCTAssertTrue(ScreenPresentation.allowsSneakPeek(type, hidingContent: false), "\(type)")
        }
    }

    func testCaptureMonitoringRunsForEitherFeature() {
        XCTAssertTrue(ScreenPresentation.needsCaptureMonitoring(recordingDetection: false, hideWhilePresenting: true))
        XCTAssertTrue(ScreenPresentation.needsCaptureMonitoring(recordingDetection: true, hideWhilePresenting: false))
        XCTAssertFalse(ScreenPresentation.needsCaptureMonitoring(recordingDetection: false, hideWhilePresenting: false))
    }

    func testFullScreenToggle() {
        XCTAssertEqual(IslandFullScreen.option(hidingAlways: true), .always)
        XCTAssertEqual(IslandFullScreen.option(hidingAlways: false), .nowPlayingOnly)
        XCTAssertTrue(IslandFullScreen.hidesAlways(.always))
        XCTAssertFalse(IslandFullScreen.hidesAlways(.nowPlayingOnly))
        XCTAssertFalse(IslandFullScreen.hidesAlways(.never))
    }

    // MARK: Timing

    private func waitUntil(_ presentation: ScreenPresentation, is expected: Bool, timeout: TimeInterval = 2) {
        let reached = expectation(description: "isHidingContent == \(expected)")
        let cancellable = presentation.$isHidingContent.sink { if $0 == expected { reached.fulfill() } }
        wait(for: [reached], timeout: timeout)
        cancellable.cancel()
    }

    func testALastingCaptureHidesContentAndItComesBackWhenItEnds() {
        let capturing = CurrentValueSubject<Bool, Never>(false)
        let presentation = ScreenPresentation()
        presentation.connect(capturing: capturing.eraseToAnyPublisher(), setting: Just(true).eraseToAnyPublisher(),
                             activationDelay: 0.1)
        XCTAssertFalse(presentation.isHidingContent)

        capturing.send(true)
        XCTAssertFalse(presentation.isHidingContent)        // not before the delay
        waitUntil(presentation, is: true)

        capturing.send(false)
        waitUntil(presentation, is: false)
    }

    func testAMomentaryCaptureLikeAScreenshotHidesNothing() {
        let capturing = CurrentValueSubject<Bool, Never>(false)
        let presentation = ScreenPresentation()
        presentation.connect(capturing: capturing.eraseToAnyPublisher(), setting: Just(true).eraseToAnyPublisher(),
                             activationDelay: 0.3)
        var everHidden = false
        let cancellable = presentation.$isHidingContent.sink { if $0 { everHidden = true } }
        capturing.send(true)
        capturing.send(false)
        let settled = expectation(description: "past the delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertFalse(everHidden)
        cancellable.cancel()
    }

    func testWithTheSettingOffNothingIsHidden() {
        let presentation = ScreenPresentation()
        presentation.connect(capturing: Just(true).eraseToAnyPublisher(), setting: Just(false).eraseToAnyPublisher(),
                             activationDelay: 0)
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertFalse(presentation.isHidingContent)
    }
}

/// New screenshots while the screen is shared: collected, but no flash and
/// no switch to the Screenshots tab. Restores every setting it touches.
@MainActor
final class ScreenshotsWhilePresentingTests: XCTestCase {
    private var savedAutoOpen = true
    private var savedHidden: [NotchTab] = []
    private var savedShelf = true
    private var savedView: NotchViews = .home

    override func setUp() {
        super.setUp()
        savedAutoOpen = Defaults[.openScreenshotsOnNewScreenshot]
        savedHidden = Defaults[.notchHiddenTabs]
        savedShelf = Defaults[.enableScreenshotShelf]
        savedView = DynamicIslandViewCoordinator.shared.currentView
        Defaults[.openScreenshotsOnNewScreenshot] = true
        Defaults[.notchHiddenTabs] = []
        Defaults[.enableScreenshotShelf] = true
    }

    override func tearDown() {
        Defaults[.openScreenshotsOnNewScreenshot] = savedAutoOpen
        Defaults[.notchHiddenTabs] = savedHidden
        Defaults[.enableScreenshotShelf] = savedShelf
        DynamicIslandViewCoordinator.shared.currentView = savedView
        super.tearDown()
    }

    func testAScreenshotDuringPresentingIsCollectedQuietly() throws {
        let capturing = CurrentValueSubject<Bool, Never>(true)
        let presentation = ScreenPresentation()
        presentation.connect(capturing: capturing.eraseToAnyPublisher(), setting: Just(true).eraseToAnyPublisher(),
                             activationDelay: 0)
        let hidden = expectation(description: "presenting")
        let watch = presentation.$isHidingContent.sink { if $0 { hidden.fulfill() } }
        wait(for: [hidden], timeout: 2)
        watch.cancel()

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-presenting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.png")
        let second = folder.appendingPathComponent("second.png")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)

        let manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))
        manager.presentation = presentation
        DynamicIslandViewCoordinator.shared.currentView = .home

        manager.didCapture(first, at: Date())
        XCTAssertEqual(manager.store.batches.flatMap(\.items).count, 1)   // collected
        XCTAssertNil(manager.flash)                                        // no flash
        XCTAssertEqual(DynamicIslandViewCoordinator.shared.currentView, .home) // no tab switch

        // Sharing ends: the next screenshot is announced again.
        capturing.send(false)
        let shown = expectation(description: "not presenting")
        let watchEnd = presentation.$isHidingContent.sink { if !$0 { shown.fulfill() } }
        wait(for: [shown], timeout: 2)
        watchEnd.cancel()

        manager.didCapture(second, at: Date())
        XCTAssertNotNil(manager.flash)
        // Screenshots are part of the Clipboard tab since step D4.
        XCTAssertEqual(DynamicIslandViewCoordinator.shared.currentView, .clipboard)
    }
}
