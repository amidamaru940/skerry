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
import ApplicationServices

/// Pastes a clipboard entry into the app the user was working in.
///
/// The island is a non-activating panel: after a click in it, key events go
/// to the island while the user's app stays active. So pasting is: put the
/// entry on the clipboard (as the app's own write), close the island, hand
/// activation back to the last app that was in front, then press ⌘V. Pressing
/// keys for another app needs the Accessibility permission; without it the
/// entry is only copied and the user presses ⌘V.
@MainActor
enum ClipboardPaster {
    enum Result: Equatable {
        case pasted
        /// Copied, but ⌘V could not be sent (no Accessibility permission or no target app).
        case copiedOnly
        /// Nothing could be copied (the files are gone): the island stays
        /// open and nothing is pressed, so the clipboard's earlier content
        /// is not pasted instead.
        case nothingCopied
    }

    // Replaced in tests, so nothing is pressed or activated on the machine.
    static var isAccessibilityTrusted: () -> Bool = { AXIsProcessTrusted() }
    static var activateTarget: (NSRunningApplication) -> Void = { $0.activate() }
    static var postPasteKeystroke: () -> Void = { postCommandV() }
    static var pasteDelay: TimeInterval = 0.15
    /// The pause after each ⌘V of a one-by-one paste, for the target app to
    /// read the clipboard before the next piece replaces it.
    static var pieceGap: TimeInterval = 0.25
    /// Waits between the steps of a paste run. It suspends the run without
    /// blocking the main thread or leaving a timer behind; replaced in tests.
    static var pause: (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    /// The app in front now, by its process; replaced in tests.
    static var frontmostProcessID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    /// Whether an island holds the keyboard, so a ⌘V would go to it; replaced in tests.
    static var islandHasKeyboard: () -> Bool = { NSApp.keyWindow is DynamicIslandWindow }
    /// Hands the keyboard back from the closed island to the app in front
    /// before the ⌘V; replaced in tests.
    static var returnIslandKeyboard: () -> Void = { DynamicIslandWindow.returnKeyboardFromIslands() }

    /// The one-by-one paste under way, if any (see `deliverOneByOne`).
    private(set) static var pasteRun: Task<Void, Never>?
    private static var pasteRunID = UUID()
    /// A copy of screenshots still being prepared (⌘C), if any: it writes
    /// the clipboard a moment later (see `startCopy`).
    private(set) static var pendingCopy: Task<Int, Never>?

    /// The last app other than Skerry that was in front.
    private(set) static var lastExternalApp: NSRunningApplication?
    private static var activationObserver: NSObjectProtocol?

    /// Starts following which app is in front (called at launch).
    static func trackFrontmostApps() {
        guard activationObserver == nil else { return }
        remember(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { remember(app) }
        }
    }

    static func remember(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              RecentApps.isUserApp(app.activationPolicy) else { return }
        lastExternalApp = app
        if RecentApps.isPasteTarget(bundleID: app.bundleIdentifier) {
            recentExternalApps = RecentApps.remembering(app, in: recentExternalApps, same: { $0.processIdentifier == $1.processIdentifier })
        }
        PasteTarget.shared.update(app.localizedName)
    }

    /// The last three apps other than Skerry and Finder that were in front,
    /// newest first: the «куда» arrow of the paste key (Buffer v3, Q11).
    private(set) static var recentExternalApps: [NSRunningApplication] = []

    /// The recent apps still running, for the arrow's list: never Finder
    /// (⌘V there copies the screenshot files into the open folder), never
    /// Skerry, never an app that has quit.
    static var pasteTargets: [NSRunningApplication] {
        RecentApps.targets(recentExternalApps, bundleID: { $0.bundleIdentifier }, isTerminated: { $0.isTerminated })
    }

    /// Copies `item` (plain text when `plainText` and the entry has text),
    /// closes the island and pastes into the last app in front.
    @discardableResult
    static func paste(
        _ item: ClipboardItem,
        plainText: Bool,
        manager: ClipboardManager = .shared,
        pasteboard: NSPasteboard = .general,
        target: NSRunningApplication? = nil,
        closeIsland: () -> Void
    ) -> Result {
        let hasText = item.stringData != nil || item.type == .file
        return deliver(target: target, closeIsland: closeIsland) {
            manager.copyToClipboard(item, plainText: plainText && hasText, to: pasteboard)
        }
    }

    /// Puts content on the clipboard with `write` (which marks it as the
    /// app's own), then closes the island, hands activation back to the last
    /// app in front and presses ⌘V there. Without Accessibility (or with no
    /// app to paste into) the island stays open, so it can say "press ⌘V".
    @discardableResult
    static func deliver(target: NSRunningApplication? = nil, closeIsland: () -> Void, write: () -> Void) -> Result {
        yieldClipboard()
        write()
        guard isAccessibilityTrusted(), let app = target ?? lastExternalApp else { return .copiedOnly }
        closeIsland()
        returnIslandKeyboard()
        activateTarget(app)
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            postPasteKeystroke()
        }
        return .pasted
    }

    /// One step of pasting several pieces one by one.
    enum Step: Equatable {
        /// Put piece `index` alone on the clipboard.
        case write(Int)
        case wait(TimeInterval)
        case pressCommandV
    }

    /// The steps for `count` pieces: the first is pasted as `deliver` does
    /// it (write, `pasteDelay` for the activation, ⌘V); each next one waits
    /// `pieceGap` after the previous ⌘V, then is written and pasted.
    static func plan(count: Int) -> [Step] {
        guard count > 0 else { return [] }
        var steps: [Step] = [.write(0), .wait(pasteDelay), .pressCommandV]
        for index in 1..<count {
            steps += [.wait(pieceGap), .write(index), .pressCommandV]
        }
        return steps
    }

    /// Pastes `count` pieces (screenshots) into the target one after another.
    /// Claude, Chrome (Chromium, Electron) and Telegram take a single picture
    /// per ⌘V, so several pictures on the clipboard at once gave one at most.
    ///
    /// The island closes and the target comes forward at once; then the run
    /// follows `plan`, and each `.write` first makes its piece off the main
    /// thread (`prepare`), so one piece at a time is in memory. A piece that
    /// can no longer be made is left out, and no ⌘V is pressed for it. The
    /// waits suspend, nothing blocks the main thread, and nothing keeps
    /// running after the last ⌘V. Afterwards the clipboard holds the last
    /// piece alone.
    ///
    /// Right before each ⌘V the run checks that the target is still in
    /// front and that no island is open or holds the keyboard
    /// (`isIslandOpen`, `islandHasKeyboard`): the pieces never go into
    /// another app or into the island. When that fails, the pieces not yet
    /// pasted are copied together (`writeTogether`) and `onStopped` gets
    /// their count, for a "press ⌘V" hint. A newer paste or copy, or a
    /// history entry or colour copied meanwhile (`yieldClipboard`), stops
    /// the run with nothing more written: the clipboard is theirs.
    ///
    /// With `count` 0 nothing is closed, written or pressed (`.nothingCopied`):
    /// a ⌘V would paste whatever was on the clipboard before. Without
    /// Accessibility or an app to paste into, all pieces are copied together
    /// for the user's own ⌘V, as `deliver` does.
    @discardableResult
    static func deliverOneByOne<Piece>(
        count: Int,
        target: NSRunningApplication? = nil,
        isIslandOpen: @escaping @MainActor () -> Bool = { false },
        closeIsland: () -> Void,
        prepare: @escaping @MainActor (Int) async -> Piece?,
        writeOne: @escaping @MainActor (Piece) -> Void,
        writeTogether: @escaping @MainActor (Range<Int>) async -> Int,
        onStopped: @escaping @MainActor (Int) -> Void = { _ in }
    ) -> Result {
        guard count > 0 else { return .nothingCopied }
        yieldClipboard()
        guard isAccessibilityTrusted(), let app = target ?? lastExternalApp else {
            startRun { _ = await writeTogether(0..<count) }
            return .copiedOnly
        }
        closeIsland()
        returnIslandKeyboard()
        activateTarget(app)
        startRun {
            // The piece on the clipboard and not pasted yet; nil while its
            // file was gone, so the ⌘V after it is not pressed (it would
            // paste the previous piece again, or the clipboard's earlier
            // content).
            var onClipboard: Int?
            for step in plan(count: count) {
                guard !Task.isCancelled else { return }
                switch step {
                case .write(let index):
                    let piece = await prepare(index)
                    guard !Task.isCancelled else { return }
                    onClipboard = piece == nil ? nil : index
                    if let piece { writeOne(piece) }
                case .wait(let seconds):
                    await pause(seconds)
                case .pressCommandV:
                    guard let index = onClipboard else { continue }
                    // Checked with no suspension before the key press.
                    guard keysReach(app, isIslandOpen: isIslandOpen) else {
                        let copied = await writeTogether(index..<count)
                        guard !Task.isCancelled, copied > 0 else { return }
                        onStopped(copied)
                        return
                    }
                    postPasteKeystroke()
                    onClipboard = nil
                }
            }
        }
        return .pasted
    }

    /// Whether a ⌘V now reaches `app`: it is still in front, and no island
    /// is open or holds the keyboard.
    static func keysReach(_ app: NSRunningApplication, isIslandOpen: () -> Bool) -> Bool {
        frontmostProcessID() == app.processIdentifier && !isIslandOpen() && !islandHasKeyboard()
    }

    /// Stops a one-by-one paste under way: a newer paste or copy takes the
    /// clipboard.
    static func stopPasting() {
        pasteRun?.cancel()
        pasteRun = nil
    }

    /// Something else takes the clipboard now (a newer paste or copy, a
    /// history entry, a colour): a paste run under way and a copy still
    /// being prepared stop, so neither overwrites it a moment later.
    static func yieldClipboard() {
        stopPasting()
        pendingCopy?.cancel()
        pendingCopy = nil
    }

    /// `yieldClipboard` for the writers that are not on the main actor by
    /// type (`ClipboardManager`, `ColorPickerManager`); they are called from
    /// the interface, on the main thread.
    nonisolated static func yieldClipboardFromAnyThread() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { yieldClipboard() }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { yieldClipboard() } }
        }
    }

    /// Starts a copy that writes the clipboard when its pieces are ready
    /// (⌘C on screenshots); it replaces a paste run and an earlier copy, and
    /// `yieldClipboard` stops it. The task answers how many pieces went.
    @discardableResult
    static func startCopy(_ body: @escaping @MainActor () async -> Int) -> Task<Int, Never> {
        yieldClipboard()
        let task = Task { @MainActor in await body() }
        pendingCopy = task
        return task
    }

    private static func startRun(_ body: @escaping @MainActor () async -> Void) {
        let id = UUID()
        pasteRunID = id
        pasteRun = Task { @MainActor in
            await body()
            if pasteRunID == id { pasteRun = nil }
        }
    }

    /// The name of the app a paste goes to, for "Paste into Claude".
    static var targetName: String? {
        lastExternalApp?.localizedName
    }

    /// Presses ⌘V. Key code 9 is the physical V key, so it works in any
    /// keyboard layout (macOS maps ⌘ shortcuts through the Latin layout).
    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}

/// The newest-first list behind the paste key's arrow.
enum RecentApps {
    static let limit = 3
    /// Apps a paste never goes to from the arrow.
    static let excludedBundleIDs: Set<String> = ["com.apple.finder"]

    /// Only apps with a Dock icon take a paste. The macOS prompt asking for
    /// Accessibility after a reinstall (universalAccessAuthWarn) came forward
    /// and sat in the arrow's list; its ⌘V only beeped (23.10).
    static func isUserApp(_ policy: NSApplication.ActivationPolicy) -> Bool {
        policy == .regular
    }

    static func isPasteTarget(bundleID: String?, own: String? = Bundle.main.bundleIdentifier) -> Bool {
        guard let bundleID else { return true }
        return bundleID != own && !excludedBundleIDs.contains(bundleID)
    }

    static func targets<App>(_ apps: [App], bundleID: (App) -> String?, isTerminated: (App) -> Bool,
                             own: String? = Bundle.main.bundleIdentifier) -> [App] {
        apps.filter { !isTerminated($0) && isPasteTarget(bundleID: bundleID($0), own: own) }
    }

    static func remembering<App>(_ app: App, in list: [App], same: (App, App) -> Bool) -> [App] {
        Array(([app] + list.filter { !same($0, app) }).prefix(limit))
    }
}
