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

import Foundation

/// The one folder the app writes its own files to:
/// `~/Library/Application Support/<bundle identifier>/`.
///
/// Upstream Atoll used a fixed `DynamicIsland` folder, which any Atoll install
/// would share, and the iCloud-synced `~/Documents` for clipboard, note and
/// assistant files. Keying the folder by bundle identifier keeps this build's
/// data apart (Debug and Release get separate folders) and off iCloud.
enum AppDataDirectory {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.amidamaru940.skerry", isDirectory: true)
    }()

    /// A subfolder of `root`, created if it does not exist yet.
    static func folder(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
