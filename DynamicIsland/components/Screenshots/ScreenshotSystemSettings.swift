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

import Defaults
import Foundation

/// Changes the macOS screenshot settings the way Terminal would
/// (`defaults write com.apple.screencapture …` then restarting
/// SystemUIServer). Only called after the user confirms in Settings.
enum ScreenshotSystemSettings {
    struct Command: Equatable {
        let executable: String
        let arguments: [String]
    }

    /// Runs a command and returns its exit status. Replaced in tests, so the
    /// tests never touch the real screenshot settings.
    static var runner: (Command) -> Int32 = { command in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private static let domain = ScreenshotLocation.preferencesDomain
    private static let restartSystemUI = Command(executable: "/usr/bin/killall", arguments: ["SystemUIServer"])

    // MARK: Location

    static func useFolderCommands(_ folder: URL) -> [Command] {
        [Command(executable: "/usr/bin/defaults", arguments: ["write", domain, "location", folder.path]), restartSystemUI]
    }

    /// Creates the folder and makes macOS save screenshots there.
    @discardableResult
    static func useFolder(_ folder: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return false
        }
        return useFolderCommands(folder).map(runner).first ?? -1 == 0
    }

    // MARK: Floating thumbnail

    /// macOS shows the floating thumbnail unless `show-thumbnail` is false;
    /// while it shows, the file is only written once the thumbnail goes away.
    static var isFloatingThumbnailShown: Bool {
        (UserDefaults(suiteName: domain)?.object(forKey: "show-thumbnail") as? Bool) ?? true
    }

    /// True after Skerry hid the thumbnail, until that is undone.
    static var canUndoHideThumbnail: Bool { Defaults[.screenshotThumbnailPreviousValue] != nil }

    static func hideThumbnailCommands() -> [Command] {
        [Command(executable: "/usr/bin/defaults", arguments: ["write", domain, "show-thumbnail", "-bool", "false"]), restartSystemUI]
    }

    /// Restores the value saved by `hideFloatingThumbnail`.
    static func undoHideThumbnailCommands(previous: String) -> [Command] {
        let restore = previous == "unset"
            ? Command(executable: "/usr/bin/defaults", arguments: ["delete", domain, "show-thumbnail"])
            : Command(executable: "/usr/bin/defaults", arguments: ["write", domain, "show-thumbnail", "-bool", previous])
        return [restore, restartSystemUI]
    }

    static func hideFloatingThumbnail() {
        if Defaults[.screenshotThumbnailPreviousValue] == nil {
            let current = UserDefaults(suiteName: domain)?.object(forKey: "show-thumbnail") as? Bool
            Defaults[.screenshotThumbnailPreviousValue] = current.map { $0 ? "true" : "false" } ?? "unset"
        }
        hideThumbnailCommands().forEach { _ = runner($0) }
    }

    static func undoHideFloatingThumbnail() {
        guard let previous = Defaults[.screenshotThumbnailPreviousValue] else { return }
        undoHideThumbnailCommands(previous: previous).forEach { _ = runner($0) }
        Defaults[.screenshotThumbnailPreviousValue] = nil
    }
}
