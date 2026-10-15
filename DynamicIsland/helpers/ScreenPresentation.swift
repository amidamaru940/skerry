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

import Combine
import Defaults
import Foundation

/// While the screen is shared or recorded (and `hideContentWhilePresenting`
/// is on), the island keeps private things out of view: the Clipboard and
/// Screenshots tabs show only their titles, the screenshot flash and content
/// sneak peeks stay off, and the island windows are excluded from capture
/// where macOS honours that.
///
/// "Shared or recorded" is `ScreenRecordingManager.isRecording`, i.e. some
/// app captures the screen (`CGSIsScreenWatcherPresent`). It has to last
/// `activationDelay` first, so a still screenshot never counts; it ends as
/// soon as the capture does.
final class ScreenPresentation: ObservableObject, @unchecked Sendable {
    static let shared = ScreenPresentation()
    static let activationDelay: TimeInterval = 2

    @Published private(set) var isHidingContent = false
    private var cancellable: AnyCancellable?

    /// Wires the inputs (at launch for `shared`, in tests for an own instance).
    func connect(
        capturing: AnyPublisher<Bool, Never>,
        setting: AnyPublisher<Bool, Never>,
        activationDelay: TimeInterval = ScreenPresentation.activationDelay
    ) {
        let lastingCapture = capturing
            .removeDuplicates()
            .map { capturing -> AnyPublisher<Bool, Never> in
                capturing
                    ? Just(true).delay(for: .seconds(activationDelay), scheduler: DispatchQueue.main).eraseToAnyPublisher()
                    : Just(false).eraseToAnyPublisher()
            }
            .switchToLatest()

        cancellable = Publishers.CombineLatest(setting.removeDuplicates(), lastingCapture.prepend(false))
            .map { Self.hidesContent(setting: $0, capturing: $1) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hiding in self?.isHidingContent = hiding }
    }

    static func hidesContent(setting: Bool, capturing: Bool) -> Bool {
        setting && capturing
    }

    /// System HUDs (volume, brightness, keyboard light, microphone, Caps
    /// Lock) still show; everything that tells what you are doing does not.
    static func allowsSneakPeek(_ type: SneakContentType, hidingContent: Bool) -> Bool {
        guard hidingContent else { return true }
        switch type {
        case .volume, .brightness, .backlight, .mic, .capsLock:
            return true
        case .music, .battery, .download, .timer, .reminder, .recording, .doNotDisturb,
             .bluetoothAudio, .privacy, .lockScreen, .extensionLiveActivity:
            return false
        }
    }

    /// Screen-capture monitoring runs for the recording indicator or for this.
    static func needsCaptureMonitoring(recordingDetection: Bool, hideWhilePresenting: Bool) -> Bool {
        recordingDetection || hideWhilePresenting
    }
}

/// "Hide the island in full-screen apps" in Layout, over upstream's
/// three-way `hideNotchOption` (also in Media).
enum IslandFullScreen {
    static func hidesAlways(_ option: HideNotchOption) -> Bool { option == .always }

    /// On: hide in every full-screen app. Off: back to the default, hiding
    /// only when the app playing music is in full screen.
    static func option(hidingAlways: Bool) -> HideNotchOption {
        hidingAlways ? .always : .nowPlayingOnly
    }
}
