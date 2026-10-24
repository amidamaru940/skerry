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
import Combine
import XCTest

/// A film started in Chrome after it went full screen kept the island over
/// it: the hide was computed at the Space change, while Chrome was not yet
/// the music source, and never again. These tests change the source, the
/// option and the system signals with no Space change in between.
@MainActor
final class FullscreenMediaDetectorTests: XCTestCase {
    private let screen = "Screen X"

    /// The detector's world, owned by the test: nothing here reads
    /// MacroVisionKit, Accessibility or the owner's settings. The source is
    /// silent until a test sends one, so no recompute is pending at start.
    private final class World {
        var apps: [FullscreenMediaDetector.FullscreenApp] = []
        var screens: [String] = []
        var enabled = true
        let option = CurrentValueSubject<HideNotchOption, Never>(.nowPlayingOnly)
        let source = PassthroughSubject<String?, Never>()
        let workspace = NotificationCenter()
        let app = NotificationCenter()
        var reads = 0
        var onRead: (() -> Void)?

        var inputs: FullscreenMediaDetector.Inputs {
            FullscreenMediaDetector.Inputs(
                fullscreenApps: { [weak self] in
                    guard let self else { return [] }
                    self.reads += 1
                    self.onRead?()
                    return self.apps
                },
                screenNames: { [weak self] in self?.screens ?? [] },
                isEnabled: { [weak self] in self?.enabled ?? false },
                hideOption: { [weak self] in self?.option.value ?? .never },
                hideOptionChanges: option.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                musicSource: source.eraseToAnyPublisher(),
                workspaceCenter: workspace,
                appCenter: app
            )
        }
    }

    private var world: World!
    private var detector: FullscreenMediaDetector!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        world = World()
        cancellables = []
    }

    override func tearDown() {
        cancellables = []
        detector = nil
        world = nil
        super.tearDown()
    }

    private func start(fullScreen bundleID: String, release: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(300)) {
        world.screens = [screen]
        world.apps = [.init(bundleIdentifier: bundleID, screenName: screen, isNativeFullscreen: { true })]
        detector = FullscreenMediaDetector(inputs: world.inputs, musicSourceRelease: release)
    }

    /// Waits until the hide on the test screen is `hidden`.
    private func expect(_ hidden: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let reached = expectation(description: message)
        reached.assertForOverFulfill = false
        let screen = self.screen
        let subscription = detector.$fullscreenStatus
            .sink { status in
                if (status[screen] ?? false) == hidden { reached.fulfill() }
            }
        wait(for: [reached], timeout: 3)
        subscription.cancel()
        XCTAssertEqual(detector.fullscreenStatus[screen] ?? false, hidden, message, file: file, line: line)
    }

    /// Waits for the next recompute after `signal`.
    private func recompute(after signal: () -> Void, file: StaticString = #filePath, line: UInt = #line) {
        let read = expectation(description: "recomputed")
        read.assertForOverFulfill = false
        world.onRead = { read.fulfill() }
        signal()
        wait(for: [read], timeout: 3)
        world.onRead = nil
    }

    private func postSpaceChange() {
        world.workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    // (a) The film starts after the Space change.
    private func checkSourceArrivesAfterTheSpaceChange(_ bundleID: String) {
        start(fullScreen: bundleID)
        recompute(after: postSpaceChange)
        XCTAssertEqual(detector.fullscreenStatus[screen], false, "nothing plays yet")

        world.source.send(bundleID)
        expect(true, "\(bundleID) became the source with no Space change")
    }

    // (b) Another app takes the music while the browser stays full screen.
    private func checkAnotherSourceShowsTheIsland(_ bundleID: String) {
        start(fullScreen: bundleID)
        world.source.send(bundleID)
        expect(true, "\(bundleID) plays full screen")

        world.source.send("com.apple.Music")
        expect(false, "the music moved to Music")
    }

    // (c) The option changes with no Space change.
    private func checkTheOptionApplies(_ bundleID: String) {
        start(fullScreen: bundleID)
        world.source.send(bundleID)
        expect(true, "\(bundleID) plays full screen")

        world.option.send(.never)
        expect(false, "never hide")

        world.option.send(.nowPlayingOnly)
        expect(true, "hide again while the music app is full screen")
    }

    func testChromeSourceAfterTheSpaceChangeHides() {
        checkSourceArrivesAfterTheSpaceChange("com.google.Chrome")
    }

    func testChromeLosingTheMusicShowsTheIsland() {
        checkAnotherSourceShowsTheIsland("com.google.Chrome")
    }

    func testChromeFollowsTheHideOption() {
        checkTheOptionApplies("com.google.Chrome")
    }

    // (d) The same for Safari.
    func testSafariSourceAfterTheSpaceChangeHides() {
        checkSourceArrivesAfterTheSpaceChange("com.apple.Safari")
    }

    func testSafariLosingTheMusicShowsTheIsland() {
        checkAnotherSourceShowsTheIsland("com.apple.Safari")
    }

    func testSafariFollowsTheHideOption() {
        checkTheOptionApplies("com.apple.Safari")
    }

    /// Chrome flips between itself and nothing while a film plays: the
    /// first Chrome hides at once, the short gaps change nothing.
    func testAFlappingSourceIsOneRecompute() {
        start(fullScreen: "com.google.Chrome")
        recompute(after: postSpaceChange)
        let before = world.reads

        for source in ["com.google.Chrome", nil, "com.google.Chrome", nil, "com.google.Chrome"] {
            world.source.send(source)
        }
        expect(true, "the last source is Chrome")
        XCTAssertEqual(world.reads, before + 1)

        let again = expectation(description: "no further recompute")
        again.isInverted = true
        world.onRead = { again.fulfill() }
        wait(for: [again], timeout: 0.4)
        world.onRead = nil
    }

    /// A gap in Chrome's session shorter than the release keeps the film clear.
    func testABriefGapKeepsTheIslandHidden() {
        start(fullScreen: "com.google.Chrome", release: .seconds(2))
        world.source.send("com.google.Chrome")
        expect(true, "Chrome plays full screen")
        let before = world.reads

        world.source.send(nil)
        let quiet = expectation(description: "no recompute during the gap")
        quiet.isInverted = true
        world.onRead = { quiet.fulfill() }
        wait(for: [quiet], timeout: 0.5)
        world.onRead = nil
        world.source.send("com.google.Chrome")

        XCTAssertEqual(detector.fullscreenStatus[screen], true)
        XCTAssertEqual(world.reads, before)
    }

    /// The music really stopped: once «nothing» outlasts the release, the
    /// island is no longer held hidden for Chrome.
    func testALastingGapShowsTheIsland() {
        start(fullScreen: "com.google.Chrome", release: .milliseconds(300))
        world.source.send("com.google.Chrome")
        expect(true, "Chrome plays full screen")

        world.source.send(nil)
        expect(false, "nothing has played for longer than the release")
    }

    /// Each system signal recomputes: the Space change, an app activation
    /// and a screen change, the last one on the app's own center.
    func testEverySystemSignalRecomputes() {
        start(fullScreen: "com.google.Chrome")
        world.source.send("com.google.Chrome")
        expect(true, "Chrome plays full screen")

        world.apps = []
        recompute(after: { world.workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil) })
        XCTAssertEqual(detector.fullscreenStatus[screen], false, "left full screen, seen on activation")

        world.apps = [.init(bundleIdentifier: "com.google.Chrome", screenName: screen, isNativeFullscreen: { true })]
        recompute(after: { world.app.post(name: NSApplication.didChangeScreenParametersNotification, object: nil) })
        XCTAssertEqual(detector.fullscreenStatus[screen], true, "seen on a screen change")

        world.apps = []
        recompute(after: postSpaceChange)
        XCTAssertEqual(detector.fullscreenStatus[screen], false, "seen on a Space change")
    }

    /// The screen change is posted on the app's center, not NSWorkspace's:
    /// the old observer listened where it never arrives.
    func testTheAppListensOnTheRightCenters() {
        let live = FullscreenMediaDetector.Inputs.live
        XCTAssertTrue(live.appCenter === NotificationCenter.default)
        XCTAssertTrue(live.workspaceCenter === NSWorkspace.shared.notificationCenter)
    }
}
