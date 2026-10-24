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

/// Where macOS saves screenshots, read from `com.apple.screencapture`.
enum ScreenshotLocation {
    static let preferencesDomain = "com.apple.screencapture"

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// The folder screenshots go to right now: the `location` default when set,
    /// otherwise the Desktop, which is what macOS uses.
    static func current() -> URL {
        resolve(rawLocation: UserDefaults(suiteName: preferencesDomain)?.string(forKey: "location"), home: home)
    }

    /// Turns the raw `location` value into a folder URL. Users often write it
    /// with `~` or spaces (`defaults write … location "~/My Shots"`), and
    /// macOS itself stores plain absolute paths.
    static func resolve(rawLocation: String?, home: URL) -> URL {
        guard var raw = rawLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return home.appendingPathComponent("Desktop", isDirectory: true)
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            raw = url.path
        }
        let url: URL
        if raw == "~" {
            url = home
        } else if raw.hasPrefix("~/") {
            url = home.appendingPathComponent(String(raw.dropFirst(2)), isDirectory: true)
        } else if raw.hasPrefix("/") {
            url = URL(fileURLWithPath: raw, isDirectory: true)
        } else {
            url = home.appendingPathComponent(raw, isDirectory: true)
        }
        return url.standardizedFileURL
    }

    /// The folder the setup helper offers instead of Desktop or Documents.
    static func recommendedFolder(home: URL = home) -> URL {
        home.appendingPathComponent("Screenshots", isDirectory: true)
    }

    /// Desktop and Documents (and anything inside them) sync to iCloud when
    /// "Desktop & Documents Folders" is on, and need a separate macOS
    /// permission to read.
    static func isDesktopOrDocuments(_ folder: URL, home: URL = home) -> Bool {
        let path = folder.standardizedFileURL.path
        return ["Desktop", "Documents"].contains { name in
            let protected = home.appendingPathComponent(name, isDirectory: true).standardizedFileURL.path
            return path == protected || path.hasPrefix(protected + "/")
        }
    }

    /// Folder for screenshots taken to the clipboard, when collecting them is on.
    static func clipboardFolder(home: URL = home) -> URL {
        recommendedFolder(home: home).appendingPathComponent("Clipboard", isDirectory: true)
    }
}

/// Screenshots taken to the clipboard are not kept on the Mac (owner's
/// choice, 15.10): they live in the system's temporary folder only as long as
/// they are needed to paste or drag them — a chat takes several pictures at
/// once only as files. Deleted when removed from the batch, when the batch is
/// cleared, when Skerry starts or quits, and after a day.
enum TemporaryClipboardShots {
    static let lifetime: TimeInterval = 24 * 60 * 60

    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Skerry clipboard screenshots", isDirectory: true)
    }

    static func isTemporary(_ url: URL, in folder: URL = folder) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let root = folder.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(root + "/")
    }

    /// The folder's path as written and with its links resolved (/var is
    /// /private/var), worked out once: `holds` runs for every screenshot on
    /// every redraw of the panel.
    private static let defaultRoots = roots(of: folder)

    static func roots(of folder: URL) -> [String] {
        let written = folder.standardizedFileURL.path
        let resolved = folder.standardizedFileURL.resolvingSymlinksInPath().path
        return written == resolved ? [written] : [written, resolved]
    }

    /// Whether `path` lies in the folder, by its text alone: `path` itself
    /// is never looked up on disk, so a screenshot path on the Desktop is
    /// never touched before macOS was asked for it (§5.8). Only the
    /// temporary folder's links are resolved, once.
    static func holds(path: String) -> Bool {
        holds(path: path, roots: defaultRoots)
    }

    static func holds(path: String, in folder: URL) -> Bool {
        holds(path: path, roots: roots(of: folder))
    }

    private static func holds(path: String, roots: [String]) -> Bool {
        let standardized = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL.path
        return roots.contains { standardized.hasPrefix($0 + "/") }
    }

    static func remove(_ urls: [URL], in folder: URL = folder) {
        for url in urls where isTemporary(url, in: folder) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func removeAll(in folder: URL = folder) {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes the ones older than a day; returns whether any went.
    @discardableResult
    static func removeExpired(in folder: URL = folder, now: Date = Date()) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return false }
        var removed = false
        for file in files {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if now.timeIntervalSince(created) > lifetime {
                try? FileManager.default.removeItem(at: file)
                removed = true
            }
        }
        return removed
    }
}
