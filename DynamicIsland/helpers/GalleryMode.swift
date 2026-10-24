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
import Defaults

/// A walk through the interface for design review: launched with
/// `-SkerryGallery <folder>`, Skerry shows the closed island, every tab of
/// the open island and every page of Settings, one after another, and writes
/// each step with its window frame to `<folder>/gallery.jsonl`.
/// `scripts/design/gallery.sh` reads that log and takes the screenshots, so
/// the app needs no screen-recording permission and the pictures are exactly
/// what is on screen. Without the argument nothing here runs.
@MainActor
enum GalleryMode {
    static let argument = "-SkerryGallery"
    /// Posted with a Settings page's raw name; SettingsView selects it.
    static let selectSettingsPage = Notification.Name("io.github.amidamaru940.skerry.gallery.settingsPage")

    /// How long a step waits for animations before it is logged, and how long
    /// it then holds still for the screenshot.
    static let settle: TimeInterval = 1.4
    static let hold: TimeInterval = 1.0

    static var folder: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: argument), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static func startIfRequested(vm: DynamicIslandViewModel, islandWindow: @escaping () -> NSWindow?) {
        guard let folder else { return }
        let log = folder.appendingPathComponent("gallery.jsonl")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: log)
        } catch {
            NSLog("Skerry gallery: cannot write %@: %@", log.path, String(describing: error))
            return
        }
        NSLog("Skerry gallery: writing %@", log.path)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            await step("00-closed", window: islandWindow(), log: log)

            let coordinator = DynamicIslandViewCoordinator.shared
            let original = coordinator.currentView
            vm.open()
            for (index, tab) in NotchTabLayout.visibleTabs.enumerated() {
                coordinator.currentView = tab.view
                await step(String(format: "%02d-tab-%@", index + 1, tab.rawValue), window: islandWindow(), log: log)
            }
            coordinator.currentView = original
            vm.close()

            SettingsWindowController.shared.showWindow()
            for (index, page) in SettingsGalleryPages.all.enumerated() {
                NotificationCenter.default.post(name: selectSettingsPage, object: page)
                await step(String(format: "%02d-settings-%@", 30 + index, page), window: SettingsWindowController.shared.window, log: log)
            }
            SettingsWindowController.shared.window?.close()
            append(["step": "done"], to: log)
        }
    }

    private static func step(_ name: String, window: NSWindow?, log: URL) async {
        try? await Task.sleep(for: .seconds(settle))
        let frame = window?.frame ?? .zero
        // screencapture takes a rect from the top-left of the main display.
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        append([
            "step": name,
            "x": frame.minX,
            "y": mainHeight - frame.maxY,
            "w": frame.width,
            "h": frame.height,
        ], to: log)
        try? await Task.sleep(for: .seconds(hold))
    }

    private static func append(_ entry: [String: Any], to log: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let handle = try? FileHandle(forWritingTo: log) else { return }
        handle.seekToEndOfFile()
        handle.write(data + Data("\n".utf8))
        try? handle.close()
    }
}
