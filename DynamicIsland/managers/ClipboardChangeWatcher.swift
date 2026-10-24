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

import AppKit
import Combine
import CoreGraphics

/// The one standing poll Skerry keeps: the pasteboard's `changeCount`, once a
/// second with half a second of tolerance, and only while someone is at the
/// Mac.
///
/// macOS posts no notice when the clipboard changes, so reading its counter
/// is the only way to see a copy. The look stops when the Mac sleeps, the
/// screen sleeps or locks (`ActivityGate`), and after a minute without any
/// keyboard or pointer input: a copy needs a person, and the first input
/// afterwards starts it again with an immediate look. A change made while it
/// was stopped (Universal Clipboard, a password manager clearing the
/// clipboard) is seen then, with what the clipboard holds at that moment.
///
/// A burst of clipboard screenshots replaces the picture a few times a
/// second, so `burst()` looks ten times a second for a few seconds. Only an
/// event asks for it (the screenshot shortcut's modifiers, a screenshot
/// arriving), never the watcher itself. Main thread only.
final class ClipboardChangeWatcher {
    static let shared = ClipboardChangeWatcher()

    static let interval: TimeInterval = 1
    static let tolerance: TimeInterval = 0.5
    /// Without input for this long, the look waits for the next input.
    static let idleAfter: TimeInterval = 60
    static let burstInterval: TimeInterval = 0.1
    static let burstDuration: TimeInterval = 6
    /// Looks after an event that may put a picture on the clipboard a moment
    /// later (`nudge()`): the screenshot tool writes it 0.1–0.5 s after the
    /// selection ends.
    static let nudgeDelays: [TimeInterval] = [0.15, 0.4, 0.9]

    /// Called on every change, with the change count it was seen at.
    typealias Listener = (Int) -> Void

    let pasteboard: NSPasteboard
    private let gate: ActivityGate
    private let idleSeconds: () -> TimeInterval
    private var listeners: [UUID: Listener] = [:]
    private var lastChangeCount: Int
    private var steady: GatedTimer?
    private var burstTimer: GatedTimer?
    private var burstEnds: Date?
    private var resumeMonitors: [Any] = []
    /// ⇧⌘ held and mouse releases: the events that put screenshots on the
    /// clipboard. Installed with the first listener, for the clipboard
    /// history and the screenshot batches alike.
    private var screenshotEventMonitors: [Any] = []
    private let watchesScreenshotEvents: Bool
    private var gateSubscription: AnyCancellable?

    /// True while the look waits for input after the idle minute.
    private(set) var isWaitingForInput = false
    var isLooking: Bool { steady?.isScheduled == true || burstTimer?.isScheduled == true }
    var isBursting: Bool { burstTimer?.isScheduled == true }

    init(pasteboard: NSPasteboard = .general,
         gate: ActivityGate = .shared,
         idleSeconds: @escaping () -> TimeInterval = ClipboardChangeWatcher.secondsSinceLastInput,
         watchesScreenshotEvents: Bool? = nil) {
        self.pasteboard = pasteboard
        self.gate = gate
        self.idleSeconds = idleSeconds
        self.watchesScreenshotEvents = watchesScreenshotEvents ?? (pasteboard === NSPasteboard.general)
        lastChangeCount = pasteboard.changeCount
        steady = GatedTimer(name: "clipboard changeCount", interval: Self.interval, tolerance: Self.tolerance, gate: gate) { [weak self] in
            self?.tick()
        }
        burstTimer = GatedTimer(name: "clipboard burst", interval: Self.burstInterval, tolerance: Self.burstInterval / 5, gate: gate) { [weak self] in
            self?.burstTick()
        }
        // Back at the Mac (wake, unlock): look at once, then carry on. While
        // away, nothing waits for input: the gate holds the timer.
        gateSubscription = gate.publisher(for: .userPresent)
            .dropFirst()
            .sink { [weak self] present in
                guard let self else { return }
                self.stopWaitingForInput()
                if present, !self.listeners.isEmpty {
                    self.steady?.start()
                    self.look()
                }
            }
    }

    /// Starts looking with the first listener.
    @discardableResult
    func add(_ listener: @escaping Listener) -> UUID {
        let id = UUID()
        if listeners.isEmpty {
            lastChangeCount = pasteboard.changeCount
            steady?.start()
            startScreenshotEventMonitors()
        }
        listeners[id] = listener
        return id
    }

    /// Stops looking with the last listener.
    func remove(_ id: UUID?) {
        guard let id, listeners.removeValue(forKey: id) != nil, listeners.isEmpty else { return }
        steady?.stop()
        burstTimer?.stop()
        burstEnds = nil
        stopWaitingForInput()
        stopScreenshotEventMonitors()
    }

    /// ⌃⇧⌘3/4 and ⇧⌘5 all hold ⇧⌘: look fast for the shots that follow
    /// (seen only with Accessibility). A mouse release, seen without it, ends
    /// a ⌃⇧⌘4 selection and the ⇧⌘5 toolbar's Capture: a few looks follow.
    /// Both are events, so they cost nothing between key presses and clicks.
    /// They used to belong to the screenshot collector alone, so with
    /// "collect clipboard screenshots" off the history missed quick shots.
    private func startScreenshotEventMonitors() {
        guard watchesScreenshotEvents, screenshotEventMonitors.isEmpty else { return }
        let onFlags: (NSEvent) -> Void = { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: [.shift, .command]) else { return }
            self?.burst()
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: onFlags) {
            screenshotEventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            onFlags(event)
            return event
        }) {
            screenshotEventMonitors.append(local)
        }
        if let release = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            self?.nudge()
        }) {
            screenshotEventMonitors.append(release)
        }
    }

    private func stopScreenshotEventMonitors() {
        screenshotEventMonitors.forEach(NSEvent.removeMonitor)
        screenshotEventMonitors.removeAll()
    }

    /// Looks ten times a second for `burstDuration` from now.
    func burst() {
        guard !listeners.isEmpty, gate.allows(.userPresent) else { return }
        burstEnds = Date().addingTimeInterval(Self.burstDuration)
        stopWaitingForInput()
        steady?.start()
        burstTimer?.start()
    }

    /// A few looks right after an event that may put a screenshot on the
    /// clipboard: a mouse release ends a ⌃⇧⌘4 selection or a click on the
    /// ⇧⌘5 toolbar's Capture. The shortcut's ⇧⌘ is seen only with
    /// Accessibility; mouse releases are seen without it. Without these
    /// looks, two shots inside one once-a-second look kept only the second
    /// (21.10). Three cheap looks per click, no timer left running; a
    /// screenshot found this way starts the burst.
    func nudge() {
        guard !listeners.isEmpty, gate.allows(.userPresent) else { return }
        for delay in Self.nudgeDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                // Still someone at the Mac when it fires: a lock in between stops it.
                guard let self, !self.listeners.isEmpty, self.gate.allows(.userPresent) else { return }
                self.look()
            }
        }
    }

    /// One look now, outside the schedule.
    func look() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        for listener in Array(listeners.values) {
            listener(count)
        }
    }

    // MARK: - Schedule

    /// One scheduled look; internal so tests can run it without waiting.
    func tick() {
        look()
        guard !isBursting, idleSeconds() >= Self.idleAfter else { return }
        waitForInput()
    }

    private func burstTick() {
        look()
        if let burstEnds, Date() < burstEnds { return }
        burstEnds = nil
        burstTimer?.stop()
    }

    /// Pauses the look until the next keyboard or pointer event anywhere.
    /// The monitors fire once: the first event removes them.
    private func waitForInput() {
        guard !isWaitingForInput else { return }
        steady?.stop()
        isWaitingForInput = true
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown,
                                           .otherMouseDown, .scrollWheel, .mouseMoved]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.inputArrived()
        }) {
            resumeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.inputArrived()
            return event
        }) {
            resumeMonitors.append(local)
        }
    }

    private func inputArrived() {
        guard isWaitingForInput else { return }
        stopWaitingForInput()
        guard !listeners.isEmpty else { return }
        look()
        steady?.start()
    }

    private func stopWaitingForInput() {
        resumeMonitors.forEach(NSEvent.removeMonitor)
        resumeMonitors.removeAll()
        isWaitingForInput = false
    }

    /// Seconds since the last keyboard, mouse or trackpad event in this session.
    static func secondsSinceLastInput() -> TimeInterval {
        // kCGAnyInputEventType (~0): any kind of input.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
