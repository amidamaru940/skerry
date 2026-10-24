/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import ApplicationServices
import Combine
import Defaults
import MacroVisionKit
import SwiftUI

/// Decides, per screen, whether the closed island hides because an app is
/// full screen there. It recomputes only on events: a Space change, an app
/// activation, a screen change, a new music source, a new hide option.
@MainActor
class FullscreenMediaDetector: ObservableObject {
    /// An app whose window fills a screen. `isNativeFullscreen` asks
    /// Accessibility, so it is called only when the hide option needs it.
    struct FullscreenApp {
        let bundleIdentifier: String?
        let screenName: String
        let isNativeFullscreen: () -> Bool
    }

    /// What the hide is computed from and what recomputes it. `live` is the
    /// app; tests pass their own, without MacroVisionKit, Accessibility or
    /// the owner's settings.
    struct Inputs {
        var fullscreenApps: () -> [FullscreenApp]
        var screenNames: () -> [String]
        var isEnabled: () -> Bool
        var hideOption: () -> HideNotchOption
        /// The hide option or the detection switch changed.
        var hideOptionChanges: AnyPublisher<Void, Never>
        /// The bundle identifier of the app the music comes from.
        var musicSource: AnyPublisher<String?, Never>
        /// Where Space changes and app activations are posted.
        var workspaceCenter: NotificationCenter
        /// Where screen parameter changes are posted.
        var appCenter: NotificationCenter
    }

    /// Chrome's Now Playing session flips between Chrome and nothing while a
    /// film plays. A new source counts at once; «nothing» only once it has
    /// lasted this long, so a gap never brings the island back over the film.
    static let musicSourceRelease: DispatchQueue.SchedulerTimeType.Stride = .seconds(3)
    /// A Space change arrives while the window still animates into place.
    static let systemChangeSettle: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(500)

    static let shared = FullscreenMediaDetector(inputs: .live)

    @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private let inputs: Inputs
    private let musicSourceRelease: DispatchQueue.SchedulerTimeType.Stride
    private var musicSourceBundleID: String?
    private var cancellables = Set<AnyCancellable>()

    init(inputs: Inputs, musicSourceRelease: DispatchQueue.SchedulerTimeType.Stride = musicSourceRelease) {
        self.inputs = inputs
        self.musicSourceRelease = musicSourceRelease
        setupObservers()
        updateFullScreenStatus()
    }

    private func setupObservers() {
        let workspace = inputs.workspaceCenter
        Publishers.Merge3(
            workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            workspace.publisher(for: NSWorkspace.didActivateApplicationNotification),
            // Posted on the app's own center, never on NSWorkspace's.
            inputs.appCenter.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .debounce(for: Self.systemChangeSettle, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in self?.updateFullScreenStatus() }
        .store(in: &cancellables)

        // A source applies at once; «nothing» waits out the release, and a
        // source arriving in the meantime cancels it (switchToLatest).
        let release = musicSourceRelease
        inputs.musicSource
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .map { source -> AnyPublisher<String?, Never> in
                guard source == nil else { return Just(source).eraseToAnyPublisher() }
                return Just(nil).delay(for: release, scheduler: DispatchQueue.main).eraseToAnyPublisher()
            }
            .switchToLatest()
            .removeDuplicates()
            .sink { [weak self] source in
                self?.musicSourceBundleID = source
                self?.updateFullScreenStatus()
            }
            .store(in: &cancellables)

        inputs.hideOptionChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateFullScreenStatus() }
            .store(in: &cancellables)
    }

    private func updateFullScreenStatus() {
        guard inputs.isEnabled() else {
            let reset = Dictionary(uniqueKeysWithValues: inputs.screenNames().map { ($0, false) })
            if reset != fullscreenStatus {
                fullscreenStatus = reset
            }
            return
        }
        

        let apps = inputs.fullscreenApps()
        let names = inputs.screenNames()
        let hideOption = inputs.hideOption()

        var newStatus: [String: Bool] = [:]
        for name in names {
            newStatus[name] = apps.contains { app in
                guard app.screenName == name,
                      app.bundleIdentifier != "com.apple.finder" else { return false }

                // The notch stays on display by default (the window's collectionBehavior
                // rides along with fullscreen spaces). It only hides when the user's
                // "Hide DynamicIsland" option asks for it.
                switch hideOption {
                case .always:
                    // Hide for any app in genuine native fullscreen on this screen.
                    return app.isNativeFullscreen()
                case .nowPlayingOnly:
                    // Hide only when the currently playing media app is in fullscreen.
                    return app.bundleIdentifier == musicSourceBundleID
                        && app.isNativeFullscreen()
                case .never:
                    // Always on display; never hide.
                    return false
                }
            }
        }

        if newStatus != fullscreenStatus {
            fullscreenStatus = newStatus
            NSLog("✅ Fullscreen status: \(newStatus)")
        }
    }

    /// Confirms an app the detector flagged as screen-filling is in *genuine* native
    /// fullscreen, not merely maximized/zoomed. On a notched Mac a maximized window and a
    /// fullscreen window report nearly identical frames, so frame size alone can't tell them
    /// apart — the Accessibility `AXFullScreen` attribute can. Falls back to the detector's
    /// frame-based result when Accessibility isn't trusted (so behavior doesn't silently break).
    nonisolated static func isInNativeFullscreen(processId: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return true }

        let appElement = AXUIElementCreateApplication(processId)
        // This runs on the main actor: a busy app must not stall the island
        // for the default six seconds.
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        // Prefer the focused window, then fall back to scanning all windows.
        if let focused: AXUIElement = copyAttribute(kAXFocusedWindowAttribute as CFString, from: appElement),
           isWindowFullscreen(focused) {
            return true
        }

        if let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute as CFString, from: appElement) {
            return windows.contains { isWindowFullscreen($0) }
        }

        return false
    }

    private nonisolated static func isWindowFullscreen(_ window: AXUIElement) -> Bool {
        // "AXFullScreen" is the (undocumented but stable) attribute set true only in native
        // fullscreen; maximized/zoomed windows report false or omit it.
        let value: Bool? = copyAttribute("AXFullScreen" as CFString, from: window)
        return value ?? false
    }

    private nonisolated static func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let typed = value as? T else { return nil }
        return typed
    }
}

extension FullscreenMediaDetector.Inputs {
    /// The app: MacroVisionKit and Accessibility for the windows, Defaults
    /// for the settings, MusicManager for the music source.
    static var live: Self {
        let detector = MacroVisionKit.shared
        detector.configuration.includeSystemApps = true
        return Self(
            fullscreenApps: {
                detector.detectFullscreenApps(debug: false).map { app in
                    let processId = app.processId
                    return FullscreenMediaDetector.FullscreenApp(
                        bundleIdentifier: app.bundleIdentifier,
                        screenName: app.screen.localizedName,
                        isNativeFullscreen: { FullscreenMediaDetector.isInNativeFullscreen(processId: processId) }
                    )
                }
            },
            screenNames: { NSScreen.screens.map { $0.localizedName } },
            isEnabled: { Defaults[.enableFullscreenMediaDetection] },
            hideOption: { Defaults[.hideNotchOption] },
            hideOptionChanges: Publishers.Merge(
                Defaults.publisher(.hideNotchOption, options: []).map { _ in () },
                Defaults.publisher(.enableFullscreenMediaDetection, options: []).map { _ in () }
            )
            .eraseToAnyPublisher(),
            musicSource: MusicManager.shared.$bundleIdentifier.eraseToAnyPublisher(),
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            appCenter: NotificationCenter.default
        )
    }
}
