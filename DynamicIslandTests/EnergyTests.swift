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
import CoreAudio
import XCTest

/// The overheating fix (docs/perf/REPORT-energy.md): nothing runs on its own
/// clock while the Mac sleeps, its screen sleeps or locks, and idle means idle.
final class EnergyTests: XCTestCase {
    private var workspace: NotificationCenter!
    private var distributed: NotificationCenter!
    private var gate: ActivityGate!
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        workspace = NotificationCenter()
        distributed = NotificationCenter()
        gate = ActivityGate(initial: ActivityGate.State(), workspaceCenter: workspace, distributedCenter: distributed)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.amidamaru940.skerry.tests.energy.\(UUID().uuidString)"))
    }

    override func tearDown() {
        gate.invalidate()
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    private func post(_ event: ActivityGate.Event, on center: NotificationCenter? = nil) {
        let source = ActivityGate.notificationName(for: event)
        (center ?? (source.distributed ? distributed : workspace)).post(name: source.name, object: nil)
        // Observers are on the main queue; let any queued delivery run.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: - The gate

    func testTheGateFollowsSleepScreenLockAndSession() {
        var state = ActivityGate.State()
        XCTAssertTrue(state.userPresent)

        state = ActivityGate.apply(.screenLocked, to: state)
        XCTAssertTrue(state.screenInUse, "the lock screen is on screen")
        XCTAssertFalse(state.userPresent)

        state = ActivityGate.apply(.screensDidSleep, to: state)
        XCTAssertFalse(state.screenInUse, "closing the lid sleeps the displays")

        state = ActivityGate.apply(.willSleep, to: state)
        state = ActivityGate.apply(.didWake, to: state)
        XCTAssertFalse(state.screenInUse, "a dark wake leaves the displays asleep")

        state = ActivityGate.apply(.screensDidWake, to: state)
        state = ActivityGate.apply(.screenUnlocked, to: state)
        XCTAssertTrue(state.userPresent)

        state = ActivityGate.apply(.sessionDidResignActive, to: state)
        XCTAssertFalse(state.screenInUse, "another user's session")
        state = ActivityGate.apply(.sessionDidBecomeActive, to: state)
        XCTAssertTrue(state.userPresent)
    }

    func testTheGateHearsTheSystemNotices() {
        post(.willSleep)
        XCTAssertFalse(gate.state.systemAwake)
        post(.didWake)
        XCTAssertTrue(gate.state.systemAwake)
        post(.screenLocked)
        XCTAssertFalse(gate.state.unlocked)
        post(.screenUnlocked)
        XCTAssertTrue(gate.state.userPresent)
    }

    // MARK: - On willSleep everything is stopped

    func testOnWillSleepEverythingIsStopped() {
        // A poll, a lock-screen task, the clipboard look in a burst, and the
        // clipboard-screenshot collector on top of it.
        let poll = GatedTimer(name: "test poll", interval: 1, tolerance: 0.5, gate: gate) {}
        let lockScreen = GatedTimer(name: "test lock screen", interval: 1, tolerance: 0.5, requirement: .screenInUse, gate: gate) {}
        let watcher = ClipboardChangeWatcher(pasteboard: pasteboard, gate: gate, idleSeconds: { 0 })
        let token = watcher.add { _ in }
        watcher.burst()
        let collector = ClipboardScreenshotCollector(pasteboard: pasteboard, folder: FileManager.default.temporaryDirectory,
                                                     watcher: watcher) { _, _ in }
        collector.start()
        poll.start()
        lockScreen.start()
        XCTAssertTrue(poll.isScheduled)
        XCTAssertTrue(lockScreen.isScheduled)
        XCTAssertTrue(watcher.isLooking)
        XCTAssertTrue(watcher.isBursting)

        post(.willSleep)

        XCTAssertFalse(poll.isScheduled, "no poll while the Mac sleeps")
        XCTAssertFalse(lockScreen.isScheduled, "nor work for the lock screen")
        XCTAssertFalse(watcher.isLooking, "nor the clipboard look")
        XCTAssertFalse(watcher.isBursting)
        XCTAssertFalse(GatedTimer.scheduledNames.contains("test poll"))
        XCTAssertFalse(GatedTimer.scheduledNames.contains("test lock screen"))

        // Wake with the display on: back, without catching up.
        post(.didWake)
        XCTAssertTrue(poll.isScheduled)
        XCTAssertTrue(lockScreen.isScheduled)
        XCTAssertTrue(watcher.isLooking)

        collector.stop()
        watcher.remove(token)
        poll.stop()
        lockScreen.stop()
        XCTAssertFalse(watcher.isLooking)
    }

    func testOnWillSleepTheAppsOwnTimersStop() throws {
        try XCTSkipUnless(ActivityGate.shared.allows(.userPresent), "the screen is locked or asleep")
        // The app's gate hears NSWorkspace itself: post to the real center.
        let poll = GatedTimer(name: "test shared poll", interval: 1, tolerance: 0.5) {}
        poll.start()
        XCTAssertTrue(GatedTimer.scheduledNames.contains("test shared poll"))

        post(.willSleep, on: NSWorkspace.shared.notificationCenter)
        XCTAssertTrue(GatedTimer.scheduledNames.isEmpty,
                      "scheduled while asleep: \(GatedTimer.scheduledNames)")

        post(.didWake, on: NSWorkspace.shared.notificationCenter)
        XCTAssertTrue(poll.isScheduled)
        poll.stop()
    }

    func testTheScreenSleepingOrLockingStopsThePolls() {
        let poll = GatedTimer(name: "test poll", interval: 1, tolerance: 0.5, gate: gate) {}
        poll.start()
        post(.screensDidSleep)
        XCTAssertFalse(poll.isScheduled, "lid closed")
        post(.screensDidWake)
        XCTAssertTrue(poll.isScheduled)
        post(.screenLocked)
        XCTAssertFalse(poll.isScheduled, "locked")
        post(.screenUnlocked)
        XCTAssertTrue(poll.isScheduled)
        poll.stop()
        XCTAssertFalse(poll.isScheduled)
    }

    // MARK: - The clipboard look

    func testTheClipboardIsLookedAtOnceASecondWithHalfASecondOfTolerance() {
        XCTAssertGreaterThanOrEqual(ClipboardChangeWatcher.interval, 1)
        XCTAssertGreaterThanOrEqual(ClipboardChangeWatcher.tolerance, 0.5)
        XCTAssertLessThanOrEqual(ClipboardChangeWatcher.burstDuration, 10, "a burst is bounded")
    }

    func testTheClipboardLookSeesAChangeOnce() {
        let watcher = ClipboardChangeWatcher(pasteboard: pasteboard, gate: gate, idleSeconds: { 0 })
        var seen: [Int] = []
        let token = watcher.add { seen.append($0) }
        pasteboard.clearContents()
        pasteboard.setString("copied", forType: .string)
        watcher.look()
        watcher.look()
        XCTAssertEqual(seen.count, 1)
        watcher.remove(token)
    }

    func testAMouseReleaseLooksAFewTimesSoAQuickShotIsNotMissed() {
        // ⌃⇧⌘4 ends with a mouse release; the picture reaches the clipboard
        // a moment later. Two shots inside one once-a-second look kept only
        // the second (21.10), so a release brings a few extra looks.
        let watcher = ClipboardChangeWatcher(pasteboard: pasteboard, gate: gate, idleSeconds: { 0 })
        var seen: [Int] = []
        let token = watcher.add { seen.append($0) }
        watcher.nudge()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        pasteboard.clearContents()
        pasteboard.setString("the first shot", forType: .string)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(seen.count, 1, "seen by a nudge look, before any scheduled one")
        XCTAssertLessThanOrEqual(ClipboardChangeWatcher.nudgeDelays.count, 3, "a few looks, not a poll")
        XCTAssertLessThan(ClipboardChangeWatcher.nudgeDelays.max() ?? 0, ClipboardChangeWatcher.interval)

        // Nobody at the Mac: a release asks for nothing.
        post(.screenLocked)
        pasteboard.clearContents()
        pasteboard.setString("while locked", forType: .string)
        watcher.nudge()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(seen.count, 1)
        watcher.remove(token)
    }

    func testAfterAMinuteWithoutInputTheClipboardLookWaitsForInput() {
        var idle: TimeInterval = 0
        let watcher = ClipboardChangeWatcher(pasteboard: pasteboard, gate: gate, idleSeconds: { idle })
        let token = watcher.add { _ in }
        watcher.tick()
        XCTAssertTrue(watcher.isLooking)

        idle = ClipboardChangeWatcher.idleAfter
        watcher.tick()
        XCTAssertFalse(watcher.isLooking, "no look while nobody is at the Mac")
        XCTAssertTrue(watcher.isWaitingForInput)

        // Locking and unlocking counts as coming back.
        post(.screenLocked)
        post(.screenUnlocked)
        XCTAssertFalse(watcher.isWaitingForInput)
        XCTAssertTrue(watcher.isLooking)
        watcher.remove(token)
    }

    func testNoListenerNoLook() {
        let watcher = ClipboardChangeWatcher(pasteboard: pasteboard, gate: gate, idleSeconds: { 0 })
        XCTAssertFalse(watcher.isLooking)
        watcher.burst()
        XCTAssertFalse(watcher.isBursting, "a burst needs someone to tell")
    }

    // MARK: - Pure rules

    func testExpiryIsTheEarliestDueItemNotAMinuteTick() {
        let now = Date()
        let code = ClipboardItem(stringData: "482913", type: .text)
        let text = ClipboardItem(stringData: "meeting at 10", type: .text)
        XCTAssertNil(ClipboardManager.nextExpiry(of: [text], autoClearHours: 0, removeCodes: true),
                     "nothing ever expires: no timer at all")
        let due = try? XCTUnwrap(ClipboardManager.nextExpiry(of: [text, code], autoClearHours: 24, removeCodes: true))
        XCTAssertEqual(due?.timeIntervalSince(now) ?? 0, ClipboardManager.oneTimeCodeLifetime, accuracy: 2)
        let noCodes = ClipboardManager.nextExpiry(of: [code], autoClearHours: 24, removeCodes: false)
        XCTAssertEqual(noCodes?.timeIntervalSince(now) ?? 0, 24 * 3600, accuracy: 2)
    }

    func testTheIdleAnimationPlaysOnEventsAndHoldsOtherwise() {
        XCTAssertTrue(IdleAnimationPlayback.plays(present: true, hovering: false, firstLook: true), "going idle")
        XCTAssertFalse(IdleAnimationPlayback.plays(present: true, hovering: false, firstLook: false), "then it holds")
        XCTAssertTrue(IdleAnimationPlayback.plays(present: true, hovering: true, firstLook: false), "the pointer on it")
        XCTAssertFalse(IdleAnimationPlayback.plays(present: false, hovering: true, firstLook: true), "nobody there")
        XCTAssertLessThanOrEqual(IdleAnimationPlayback.performance, 10)
    }

    func testTheNowPlayingAdapterRunsOnlyWhileSomethingPlays() {
        XCTAssertTrue(NowPlayingController.AdapterDemand.reportCountsAsPlaying(isPlaying: true, title: "Song"))
        XCTAssertFalse(NowPlayingController.AdapterDemand.reportCountsAsPlaying(isPlaying: false, title: "Song"))
        XCTAssertFalse(NowPlayingController.AdapterDemand.reportCountsAsPlaying(isPlaying: true, title: ""))
        XCTAssertGreaterThan(NowPlayingController.AdapterDemand.idleGrace, 10, "longer than a paused track stays shown")
        // Restarts back off and stop growing at a minute.
        var delay = NowPlayingController.AdapterDemand.firstRestartDelay
        for _ in 0..<10 { delay = NowPlayingController.AdapterDemand.nextRestartDelay(after: delay) }
        XCTAssertEqual(delay, NowPlayingController.AdapterDemand.maximumRestartDelay)
    }

    func testOutputStartingIsANewProcessOutputting() {
        XCTAssertTrue(AudioOutputActivity.outputBegan(previous: [], current: [7]))
        XCTAssertTrue(AudioOutputActivity.outputBegan(previous: [7], current: [7, 9]))
        XCTAssertFalse(AudioOutputActivity.outputBegan(previous: [7, 9], current: [7]))
        XCTAssertFalse(AudioOutputActivity.outputBegan(previous: [7], current: [7]))
    }

    func testOutputStartIsHeardFromIsRunning() {
        // macOS 26 posts no IsRunningOutput change; IsRunning is what arrives
        // when a player starts or resumes (measured on the Mac, 17.10.2026).
        XCTAssertTrue(AudioOutputActivity.listenedProcessProperties.contains(kAudioProcessPropertyIsRunning))
    }

    func testAStalledDownloadStopsSampling() {
        XCTAssertLessThanOrEqual(DownloadManager.stallAfter, 120)
    }
}
