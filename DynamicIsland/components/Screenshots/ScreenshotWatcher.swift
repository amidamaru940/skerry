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

import Darwin
import Foundation

/// Reports screenshots saved to a folder after the watcher started.
///
/// Two sources feed one filter: a Spotlight query for `kMDItemIsScreenCapture`
/// (the main path) and a file-system event source on the folder (the fallback
/// when Spotlight is off or slow). macOS writes a hidden temporary file and
/// renames it, so only the final, visible file passes, and every path is
/// reported once whichever source sees it first.
final class ScreenshotWatcher {
    static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    /// Still images; screen recordings (.mov) only with `includeRecordings`.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif"]
    static let recordingExtensions: Set<String> = ["mov"]

    let folder: URL
    let startDate: Date
    let includeRecordings: Bool
    private let useSpotlight: Bool
    private let onScreenshot: (URL, Date) -> Void

    private var query: NSMetadataQuery?
    private var source: DispatchSourceFileSystemObject?
    private var knownNames: Set<String> = []
    private var reported: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - startDate: screenshots created before this are ignored.
    ///   - useSpotlight: false runs only the folder fallback (used by tests).
    ///   - onScreenshot: called on the main queue with the file and its creation date.
    init(folder: URL, startDate: Date = Date(), includeRecordings: Bool = false, useSpotlight: Bool = true,
         onScreenshot: @escaping (URL, Date) -> Void) {
        self.folder = folder.standardizedFileURL
        self.startDate = startDate
        self.includeRecordings = includeRecordings
        self.useSpotlight = useSpotlight
        self.onScreenshot = onScreenshot
    }

    deinit { stop() }

    /// Whether the folder can be listed; false usually means the macOS
    /// privacy permission for Desktop/Documents was denied.
    var canReadFolder: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        knownNames = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        startFolderMonitor()
        if useSpotlight { startSpotlightQuery() }
    }

    func stop() {
        source?.cancel()
        source = nil
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    // MARK: - Filter

    /// True when the file carries the screenshot marker macOS sets.
    static func isScreenCapture(_ url: URL) -> Bool {
        let size = getxattr(url.path, screenCaptureAttribute, nil, 0, 0, 0)
        guard size > 0 else { return false }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, screenCaptureAttribute, $0.baseAddress, size, 0, 0) }
        guard read > 0 else { return false }
        let value = try? PropertyListSerialization.propertyList(from: data.prefix(read), options: [], format: nil)
        return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
    }

    /// Reports the file if it is a new screenshot in the watched folder.
    /// `trustScreenCaptureFlag` is set for Spotlight results, which already
    /// matched `kMDItemIsScreenCapture == 1`.
    func consider(_ url: URL, trustScreenCaptureFlag: Bool = false) {
        let url = url.standardizedFileURL
        let name = url.lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        let isRecording = includeRecordings && Self.recordingExtensions.contains(fileExtension)
        guard !name.hasPrefix("."),
              Self.imageExtensions.contains(fileExtension) || isRecording,
              url.deletingLastPathComponent().path == folder.path,
              !reported.contains(url.path),
              let values = try? url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey]),
              values.isRegularFile == true else { return }

        let created = values.creationDate ?? Date()
        guard created >= startDate.addingTimeInterval(-1) else { return }
        // macOS does not mark recordings as screen captures (checked: none of
        // the .mov files here carry the marker), so a recording counts when it
        // appears while the screenshot tools run, as with clipboard screenshots.
        guard trustScreenCaptureFlag || Self.isScreenCapture(url)
                || (isRecording && ClipboardScreenshotDetector.isScreenshotToolRunning()) else { return }

        reported.insert(url.path)
        onScreenshot(url, created)
    }

    // MARK: - Folder fallback

    private func startFolderMonitor() {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .link], queue: .main)
        source.setEventHandler { [weak self] in self?.scanFolder() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func scanFolder() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let newNames = Set(names).subtracting(knownNames)
        knownNames = Set(names)
        for name in newNames {
            let url = folder.appendingPathComponent(name)
            consider(url)
            // The marker can land a moment after the file appears.
            if !reported.contains(url.standardizedFileURL.path) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.consider(url) }
            }
        }
    }

    // MARK: - Spotlight

    private func startSpotlightQuery() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K == 1", "kMDItemIsScreenCapture")
        query.searchScopes = [folder]
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            guard let self else { return }
            let keys = [NSMetadataQueryUpdateAddedItemsKey, NSMetadataQueryUpdateChangedItemsKey]
            for key in keys {
                for item in (note.userInfo?[key] as? [NSMetadataItem]) ?? [] {
                    guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                    self.consider(URL(fileURLWithPath: path), trustScreenCaptureFlag: true)
                }
            }
        })
        self.query = query
        query.start()
    }
}
