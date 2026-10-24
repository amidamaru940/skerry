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
import OSLog

/// What the clipboard-screenshot recognition decided — yes/no facts only,
/// never clipboard contents. Read with
/// `log show --predicate 'subsystem == "io.github.amidamaru940.skerry"'`.
enum ClipboardShotLog {
    static let log = OSLog(subsystem: "io.github.amidamaru940.skerry", category: "clipboardShots")

    static func note(_ message: String) {
        os_log("%{public}@", log: log, type: .debug, message)
    }
}

/// Saves screenshots taken to the clipboard (⌃⇧⌘3/4 create no file) as PNG
/// in a temporary folder (`TemporaryClipboardShots`) while "Also collect
/// clipboard screenshots" is on. What counts as a clipboard screenshot: see ClipboardScreenshotDetector.
/// The clipboard privacy rules (pause, concealed types, ignored apps) apply.
final class ClipboardScreenshotCollector {
    /// How often the clipboard is looked at during a burst. A burst of ⌃⇧⌘3
    /// replaces the clipboard picture every few tenths of a second; at 0.5 s,
    /// with the file written on the main thread in between, half of a burst
    /// was gone before anyone looked. The fast look runs only for a few
    /// seconds after an event (the screenshot shortcut's ⇧⌘ held, a
    /// screenshot arriving); otherwise the shared once-a-second look of
    /// `ClipboardChangeWatcher` is all there is.
    static let pollInterval: TimeInterval = ClipboardChangeWatcher.burstInterval

    /// The picture as it was on the clipboard, still to be written.
    struct Shot {
        let data: Data
        let isPNG: Bool
    }

    private let pasteboard: NSPasteboard
    private let folder: URL
    private var lastChangeCount: Int
    private let onSaved: (URL, Date) -> Void
    private let watcher: ClipboardChangeWatcher
    private var watcherToken: UUID?
    /// Converting and writing happen here, in order, off the main thread.
    private let writeQueue = DispatchQueue(label: "io.github.amidamaru940.skerry.clipboard-shots", qos: .userInitiated)

    init(pasteboard: NSPasteboard = .general, folder: URL = TemporaryClipboardShots.folder,
         watcher: ClipboardChangeWatcher? = nil,
         onSaved: @escaping (URL, Date) -> Void) {
        self.pasteboard = pasteboard
        self.folder = folder
        self.lastChangeCount = pasteboard.changeCount
        self.onSaved = onSaved
        self.watcher = watcher ?? (pasteboard === NSPasteboard.general ? .shared : ClipboardChangeWatcher(pasteboard: pasteboard))
    }

    var isRunning: Bool { watcherToken != nil }

    func start() {
        guard watcherToken == nil else { return }
        lastChangeCount = pasteboard.changeCount
        // The shared watcher looks fast after ⇧⌘ and a few times after a
        // mouse release (ClipboardChangeWatcher.startScreenshotEventMonitors).
        watcherToken = watcher.add { [weak self] _ in self?.poll() }
        ClipboardShotLog.note("collector started (main thread: \(Thread.isMainThread))")
    }

    func stop() {
        watcher.remove(watcherToken)
        watcherToken = nil
    }

    /// Takes a new clipboard picture before the next one replaces it; the
    /// file is written on `writeQueue`.
    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        ClipboardShotLog.note("change \(count): onlyPicture=\(ClipboardScreenshotDetector.holdsOnlyAPicture(pasteboard)) tool=\(ClipboardScreenshotDetector.isScreenshotToolRunning()) fullScreen=\(ClipboardScreenshotDetector.isFullScreenPicture(pasteboard))")
        guard let shot = Self.capture(from: pasteboard, sourceBundleID: source) else { return }
        // More of a burst may follow (the toolbar's timer, a held shortcut).
        if isRunning { watcher.burst() }
        let date = Date()
        let folder = folder, onSaved = onSaved
        writeQueue.async {
            guard let url = Self.write(shot, to: folder, date: date) else { return }
            DispatchQueue.main.async { onSaved(url, date) }
        }
    }

    /// PNG bytes when the pasteboard holds only a picture.
    static func screenshotImageData(from pasteboard: NSPasteboard) -> Data? {
        guard ClipboardScreenshotDetector.holdsOnlyAPicture(pasteboard), let shot = rawPicture(from: pasteboard) else { return nil }
        return pngData(of: shot)
    }

    /// The picture's bytes as the clipboard has them; no conversion yet.
    static func rawPicture(from pasteboard: NSPasteboard) -> Shot? {
        if let png = pasteboard.data(forType: .png) { return Shot(data: png, isPNG: true) }
        for type in [NSPasteboard.PasteboardType.tiff, .init("public.jpeg")] {
            if let data = pasteboard.data(forType: type) { return Shot(data: data, isPNG: false) }
        }
        return nil
    }

    static func pngData(of shot: Shot) -> Data? {
        if shot.isPNG { return shot.data }
        return NSBitmapImageRep(data: shot.data)?.representation(using: .png, properties: [:])
    }

    /// The clipboard picture when it is a screenshot the clipboard rules
    /// allow; nil otherwise.
    static func capture(from pasteboard: NSPasteboard, sourceBundleID: String?) -> Shot? {
        let decision = ClipboardCapturePolicy.decide(
            types: ClipboardCapturePolicy.allTypes(on: pasteboard),
            sourceBundleID: sourceBundleID,
            isPaused: Defaults[.clipboardHistoryPaused],
            ignoredApps: Defaults[.clipboardIgnoredApps]
        )
        guard decision == .record,
              !ClipboardOwnWrites.isOwnWrite(pasteboard),
              ClipboardScreenshotDetector.holdsOnlyAPicture(pasteboard),
              ClipboardScreenshotDetector.looksTaken(pasteboard),
              let shot = rawPicture(from: pasteboard) else {
            ClipboardShotLog.note("not saved: decision=\(decision) own=\(ClipboardOwnWrites.isOwnWrite(pasteboard))")
            return nil
        }
        return shot
    }

    /// Writes a captured picture to `folder` as PNG.
    static func write(_ shot: Shot, to folder: URL, date: Date) -> URL? {
        guard let png = pngData(of: shot) else {
            ClipboardShotLog.note("not saved: unreadable picture")
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = folder.appendingPathComponent("Clipboard Screenshot \(formatter.string(from: date)) \(UUID().uuidString.prefix(4)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            ClipboardShotLog.note("saved \(url.lastPathComponent)")
            return url
        } catch {
            ClipboardShotLog.note("write failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Writes the clipboard picture to `folder` and returns the file, or nil
    /// when it is not a screenshot or the clipboard rules refuse it.
    static func saveIfScreenshot(from pasteboard: NSPasteboard, sourceBundleID: String?, to folder: URL, date: Date = Date()) -> URL? {
        capture(from: pasteboard, sourceBundleID: sourceBundleID).flatMap { write($0, to: folder, date: date) }
    }
}
