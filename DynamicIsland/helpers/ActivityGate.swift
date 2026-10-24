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

/// Whether anyone can see or use Skerry right now, told by the system's own
/// notices, never by polling.
///
/// Everything that works on its own clock (polls, the Now Playing adapter,
/// log readers, network discovery, retry loops) follows this and stops when
/// the answer is no: the Mac going to sleep, the displays sleeping (closing
/// the lid sleeps them), the screen locking, another user taking the screen.
/// A dark wake (the Maintenance Sleep wakes with the lid closed) leaves the
/// displays asleep, so nothing starts again until the person is back, and
/// nothing has to catch up then: each piece only reads the current state.
///
/// Main thread only, like the managers that use it.
final class ActivityGate: ObservableObject {
    struct State: Equatable {
        var systemAwake = true
        var displaysAwake = true
        var sessionActive = true
        var unlocked = true

        /// A display is on and shows this user's session, lock screen included.
        var screenInUse: Bool { systemAwake && displaysAwake && sessionActive }
        /// Someone is at the Mac: the screen is in use and unlocked.
        var userPresent: Bool { screenInUse && unlocked }
    }

    enum Event: Equatable, CaseIterable {
        case willSleep, didWake
        case screensDidSleep, screensDidWake
        case sessionDidResignActive, sessionDidBecomeActive
        case screenLocked, screenUnlocked
    }

    /// What a piece of work needs before it may run.
    enum Requirement {
        /// Only someone at the unlocked Mac needs it: polls, retries, discovery.
        case userPresent
        /// The lock screen shows it too: the music playing on it.
        case screenInUse

        func isMet(by state: State) -> Bool {
            switch self {
            case .userPresent: return state.userPresent
            case .screenInUse: return state.screenInUse
            }
        }
    }

    static let shared = ActivityGate()

    @Published private(set) var state: State

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// The notification each event comes from, and which center posts it.
    static func notificationName(for event: Event) -> (name: Notification.Name, distributed: Bool) {
        switch event {
        case .willSleep: return (NSWorkspace.willSleepNotification, false)
        case .didWake: return (NSWorkspace.didWakeNotification, false)
        case .screensDidSleep: return (NSWorkspace.screensDidSleepNotification, false)
        case .screensDidWake: return (NSWorkspace.screensDidWakeNotification, false)
        case .sessionDidResignActive: return (NSWorkspace.sessionDidResignActiveNotification, false)
        case .sessionDidBecomeActive: return (NSWorkspace.sessionDidBecomeActiveNotification, false)
        case .screenLocked: return (Notification.Name("com.apple.screenIsLocked"), true)
        case .screenUnlocked: return (Notification.Name("com.apple.screenIsUnlocked"), true)
        }
    }

    /// Tests pass their own centers and post the notices themselves.
    init(initial: State = ActivityGate.currentSystemState(),
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         distributedCenter: NotificationCenter = DistributedNotificationCenter.default()) {
        state = initial
        for event in Event.allCases {
            let source = Self.notificationName(for: event)
            let center = source.distributed ? distributedCenter : workspaceCenter
            let token = center.addObserver(forName: source.name, object: nil, queue: .main) { [weak self] _ in
                self?.handle(event)
            }
            observers.append((center, token))
        }
    }

    /// Stops listening; for gates made by tests.
    func invalidate() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    func handle(_ event: Event) {
        let next = Self.apply(event, to: state)
        if next != state { state = next }
    }

    static func apply(_ event: Event, to state: State) -> State {
        var state = state
        switch event {
        case .willSleep: state.systemAwake = false
        case .didWake: state.systemAwake = true
        case .screensDidSleep: state.displaysAwake = false
        case .screensDidWake: state.displaysAwake = true
        case .sessionDidResignActive: state.sessionActive = false
        case .sessionDidBecomeActive:
            // The session coming back means its user is at the screen again;
            // an unlock notice may still follow, which changes nothing then.
            state.sessionActive = true
        case .screenLocked: state.unlocked = false
        case .screenUnlocked: state.unlocked = true
        }
        return state
    }

    /// Emits whether `requirement` is met, now and on every change.
    func publisher(for requirement: Requirement) -> AnyPublisher<Bool, Never> {
        $state.map { requirement.isMet(by: $0) }.removeDuplicates().eraseToAnyPublisher()
    }

    func allows(_ requirement: Requirement) -> Bool {
        requirement.isMet(by: state)
    }

    /// What the system says at launch: locked screen, sleeping main display,
    /// a session that is not on the console.
    static func currentSystemState() -> State {
        var state = State()
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            state.unlocked = !((session["CGSSessionScreenIsLocked"] as? Bool) ?? false)
            state.sessionActive = (session["kCGSSessionOnConsoleKey"] as? Bool) ?? true
        }
        state.displaysAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        return state
    }
}

/// A repeating timer that runs only while it is wanted and `ActivityGate`
/// allows it, with a tolerance so macOS can line its wakeups up with others.
///
/// Stopped by the gate, it is not fired to catch up when the gate opens again:
/// the next tick simply reads the state as it is then. Main thread only.
final class GatedTimer {
    /// Names of every gated timer that is scheduled right now, for tests and
    /// for the energy report.
    private(set) static var scheduledNames: [String] = []

    let name: String
    let interval: TimeInterval
    let tolerance: TimeInterval
    private let requirement: ActivityGate.Requirement
    private let fire: () -> Void
    private var timer: Timer?
    private var gateOpen: Bool
    private var gateSubscription: AnyCancellable?

    /// Whether the owner wants it running; it runs when this and the gate agree.
    private(set) var isWanted = false
    var isScheduled: Bool { timer != nil }

    init(name: String,
         interval: TimeInterval,
         tolerance: TimeInterval,
         requirement: ActivityGate.Requirement = .userPresent,
         gate: ActivityGate = .shared,
         fire: @escaping () -> Void) {
        self.name = name
        self.interval = interval
        self.tolerance = tolerance
        self.requirement = requirement
        self.fire = fire
        gateOpen = gate.allows(requirement)
        gateSubscription = gate.publisher(for: requirement)
            .dropFirst()
            .sink { [weak self] open in
                self?.gateOpen = open
                self?.update()
            }
    }

    deinit {
        timer?.invalidate()
        if timer != nil, let index = Self.scheduledNames.firstIndex(of: name) {
            Self.scheduledNames.remove(at: index)
        }
    }

    func start() {
        isWanted = true
        update()
    }

    func stop() {
        isWanted = false
        update()
    }

    private func update() {
        let shouldRun = isWanted && gateOpen
        if shouldRun, timer == nil {
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                self?.fire()
            }
            timer.tolerance = tolerance
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            Self.scheduledNames.append(name)
        } else if !shouldRun, let timer {
            timer.invalidate()
            self.timer = nil
            if let index = Self.scheduledNames.firstIndex(of: name) {
                Self.scheduledNames.remove(at: index)
            }
        }
    }
}
