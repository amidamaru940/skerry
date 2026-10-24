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
import CoreServices
import os

/// Whether Skerry may script Music or Spotify: macOS's Automation answer.
///
/// The first Apple Event to an app macOS has no answer for brings up its
/// question. Upstream scripted both players from launch whenever they ran, so
/// a fresh install asked before anyone touched the island (§5.8, PRM-1). Now
/// whatever Skerry does on its own -- the read at launch, a read when the
/// player posts a change, the favourite lookup, the AirPlay list when the
/// island opens -- only looks the answer up and sends nothing until it is yes.
/// A click that needs the app is the one moment to ask: a player control or
/// the AirPlay list; in Auto, a control while macOS reports the app (the
/// controller reads it once after the click, `refreshAfterClick`); choosing it
/// as the source; «Open player».
///
/// The answer is looked up off the main thread: it is a round trip to macOS,
/// and while the question is up it waits for the person. It is looked up
/// before every event nobody clicked for, so a `tccutil reset` while Skerry
/// runs is seen before the next one; before a clicked event while it is not
/// yes; and when Skerry becomes active (back from System Settings) or the app
/// launches or comes to the front. Never on a timer (rule #23).
///
/// Existing installs need no migration and Skerry keeps no flag of its own:
/// macOS keeps the answer. A Mac that allowed Skerry gets noErr at every look
/// and is scripted from launch exactly as before. One that refused gets
/// errAEEventNotPermitted and is sent nothing; before, every event failed with
/// that same error. Only a build macOS has no answer for (a fresh install, or
/// after `tccutil reset`) now waits for a click where it used to ask at launch.
/// A stored flag could only drift from what macOS says.
final class AutomationConsent: @unchecked Sendable {
    enum Status: Equatable, Sendable {
        /// noErr.
        case allowed
        /// errAEEventWouldRequireUserConsent: macOS has not asked yet.
        case notAsked
        /// errAEEventNotPermitted: the person said no, in the question or in
        /// System Settings.
        case refused
        /// procNotFound: macOS answers only about a running app.
        case notRunning
        /// Not looked up yet, or an answer this code does not know.
        case unknown

        init(_ result: OSStatus) {
            switch result {
            case OSStatus(noErr): self = .allowed
            case OSStatus(errAEEventWouldRequireUserConsent): self = .notAsked
            case OSStatus(errAEEventNotPermitted): self = .refused
            case OSStatus(procNotFound): self = .notRunning
            default: self = .unknown
            }
        }

        /// Whether this is what the person said, rather than macOS being
        /// unable to say.
        var isAnswer: Bool {
            self == .allowed || self == .notAsked || self == .refused
        }
    }

    static let music = AutomationConsent(bundleIdentifier: AutoMediaSource.appleMusicBundleID)
    static let spotify = AutomationConsent(bundleIdentifier: AutoMediaSource.spotifyBundleID)

    let bundleIdentifier: String
    private let state = OSAllocatedUnfairLock(initialState: Status.unknown)
    /// The question in progress: clicks while it is up wait for its answer
    /// instead of asking again.
    private let question = OSAllocatedUnfairLock<Task<Status, Never>?>(initialState: nil)
    private let determine: @Sendable (_ bundleIdentifier: String, _ askingUser: Bool) -> OSStatus
    private var observers = Set<AnyCancellable>()

    /// The last answer macOS gave, for code that cannot wait for a look-up.
    /// The permission row of Settings (PermissionKind, R11) is meant to read
    /// this.
    var status: Status { state.withLock { $0 } }

    init(
        bundleIdentifier: String,
        observesApps: Bool = true,
        determine: @escaping @Sendable (_ bundleIdentifier: String, _ askingUser: Bool) -> OSStatus
            = { AutomationConsent.determinePermission(bundleIdentifier: $0, askingUser: $1) }
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.determine = determine
        guard observesApps else { return }
        observeAnswerChanges()
    }

    // MARK: - Checks

    /// Before an Apple Event nobody clicked for. Never asks.
    ///
    /// Always looked up, even after a yes: `tccutil reset` takes the answer
    /// back without a notification, and the next unclicked event to an app
    /// macOS has no answer for would ask. It costs one off-main round trip per
    /// read, which only a change the player posts, the island opening or a
    /// track change starts.
    func allowsUnclickedEvent() async -> Bool {
        Self.allowsUnclickedEvent(await check(askingUser: false).kept)
    }

    /// Before an Apple Event a click on a player control (or a media key)
    /// sends: the one moment Skerry may ask (§5.8).
    func allowsClickedEvent() async -> Bool {
        let lookedUp = await lookUpForClick()
        guard AppRuntimeEnvironment.mayAskForPermissions else {
            return Self.allowsUnclickedEvent(lookedUp)
        }
        switch Self.stepForClick(lookedUp) {
        case .send:
            return true
        case .skip:
            return false
        case .ask:
            // Waits, off the main thread, for the person's answer.
            return Self.sendsAfterAsking(await ask())
        }
    }

    /// Looks the answer up again, without asking the person.
    @discardableResult
    func refresh() async -> Status {
        await check(askingUser: false).kept
    }

    /// What a click goes by: a stored yes as it is (if `tccutil` took it back,
    /// the event asks, and a click may), anything else as macOS says it now.
    /// Not the kept answer: a closed app must still get the event, which
    /// launches it as it always has. A no kept from before may have been taken
    /// back in System Settings since; if not, the event fails as it did.
    func lookUpForClick() async -> Status {
        status == .allowed ? .allowed : await check(askingUser: false).lookedUp
    }

    /// One question at a time: a second click, or a drag of the slider, waits
    /// for the answer to the first.
    private func ask() async -> Status {
        guard AppRuntimeEnvironment.mayAskForPermissions else {
            return await check(askingUser: false).lookedUp
        }
        let asking = question.withLock { current -> Task<Status, Never> in
            if let current { return current }
            let asking = Task { await self.check(askingUser: true).lookedUp }
            current = asking
            return asking
        }
        let answer = await asking.value
        question.withLock { current in
            if current == asking { current = nil }
        }
        return answer
    }

    /// `lookedUp` is what macOS said this time; `kept` is what is stored,
    /// where "not running" keeps the answer known before.
    private func check(askingUser: Bool) async -> (lookedUp: Status, kept: Status) {
        let determine = determine
        let bundleIdentifier = bundleIdentifier
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: determine(bundleIdentifier, askingUser))
            }
        }
        let lookedUp = Status(result)
        let kept = state.withLock { stored in
            stored = Self.merged(stored, with: lookedUp)
            return stored
        }
        return (lookedUp, kept)
    }

    /// The answer changes in System Settings, and these are the moments it
    /// may have. `tccutil` fires none of them; `allowsUnclickedEvent()` looks
    /// the answer up before each event instead.
    private func observeAnswerChanges() {
        let workspace = NSWorkspace.shared.notificationCenter
        let target = bundleIdentifier
        let appCameUp = workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didActivateApplicationNotification))
            .filter { note in
                (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .bundleIdentifier == target
            }
            .map { _ in () }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .map { _ in () }
            .merge(with: appCameUp)
            .sink { [weak self] in
                Task { await self?.refresh() }
            }
            .store(in: &observers)
    }

    // MARK: - Decisions

    enum ClickStep: Equatable {
        /// Allowed, or the app is not running (whatever was said before): the
        /// script launches it, as it always has, and macOS asks then if it
        /// has no answer.
        case send
        /// No answer yet: ask, then send unless the answer is no.
        case ask
        /// The person said no. Nothing is sent, so nothing fails either.
        case skip
    }

    static func allowsUnclickedEvent(_ status: Status) -> Bool {
        status == .allowed
    }

    static func stepForClick(_ status: Status) -> ClickStep {
        switch status {
        case .allowed, .notRunning: return .send
        case .notAsked, .unknown: return .ask
        case .refused: return .skip
        }
    }

    /// Anything but a no sends. If the question did not come up (macOS still
    /// has no answer, or could not ask a closed app), the event asks itself.
    static func sendsAfterAsking(_ answer: Status) -> Bool {
        answer != .refused
    }

    /// "Not running" says nothing about the answer, so it keeps the one
    /// already known.
    static func merged(_ known: Status, with lookedUp: Status) -> Status {
        lookedUp == .notRunning && known.isAnswer ? known : lookedUp
    }

    /// Asks about every event (`typeWildCard`): macOS answers per app, and
    /// Skerry sends several.
    static func determinePermission(bundleIdentifier: String, askingUser: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        return withExtendedLifetime(target) {
            AEDeterminePermissionToAutomateTarget(
                target.aeDesc,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                askingUser
            )
        }
    }
}
