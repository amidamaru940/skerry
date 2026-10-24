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
import ImageIO
import UniformTypeIdentifiers

/// What screenshots put on the clipboard, for ⌘C and «Вставить в … · N».
///
/// Each screenshot is one clipboard item carrying both its file and its
/// picture. Finder, Mail and Messages take the file; Claude, Chrome and the
/// other Chromium and Electron apps ignore file URLs and read only the
/// picture (`public.png`), so a batch written as file URLs alone pasted
/// nothing there. A picture over `maxImageBytes` (a full-screen Retina
/// shot is about 5 MB) goes downscaled; the file URL still points to the
/// original.
enum ScreenshotPasteboard {
    /// A picture larger than this goes on the clipboard downscaled.
    static let maxImageBytes = 4_500_000
    /// The longest side of a downscaled picture, in pixels. The next one is
    /// tried only while the picture is still over `maxImageBytes`.
    static let downscaledSides = [2560, 1920, 1280]

    /// One screenshot as it goes on the clipboard.
    struct Shot: Sendable {
        let url: URL
        /// PNG data; nil for a file that is not a picture (a screen recording).
        let png: Data?
    }

    /// The files that are still there. Cheap, so it is asked on the main
    /// thread before anything is closed or pressed.
    static func existing(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Reads one screenshot and downscales it when large, off the main
    /// thread; nil when its file is gone. Callers take one at a time, so a
    /// single picture is in memory and a cancelled run starts no next one.
    static func prepare(_ url: URL) async -> Shot? {
        await Task.detached(priority: .userInitiated) { shot(for: url) }.value
    }

    static func shot(for url: URL) -> Shot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Shot(url: url, png: pngData(for: url))
    }

    /// The picture of `url` as PNG: the file itself when it is a PNG of at
    /// most `maxImageBytes`, otherwise encoded (and downscaled when larger).
    static func pngData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) else { return nil }
        let isPNG = (type as String) == UTType.png.identifier
        if isPNG, let size = fileSize(url), size <= maxImageBytes {
            return try? Data(contentsOf: url)
        }
        if !isPNG, let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let full = encodePNG(image), full.count <= maxImageBytes {
            return full
        }
        return downscaledPNG(source)
    }

    /// The picture at the largest of `downscaledSides` that fits in
    /// `maxImageBytes`; the smallest one when none does.
    static func downscaledPNG(_ source: CGImageSource) -> Data? {
        var smallest: Data?
        for side in downscaledSides {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let data = encodePNG(image) else { break }
            smallest = data
            if data.count <= maxImageBytes { break }
        }
        return smallest
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func fileSize(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    /// One clipboard item: the file first, then its picture.
    static func item(for shot: Shot) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(shot.url.absoluteString, forType: .fileURL)
        if let png = shot.png {
            item.setData(png, forType: .png)
        }
        return item
    }

    /// Clears the clipboard and puts `shots` on it, one item each, as the
    /// app's own write (the clipboard history does not record it).
    @MainActor
    static func write(_ shots: [Shot], to pasteboard: NSPasteboard) {
        ClipboardOwnWrites.write(to: pasteboard) { pasteboard in
            pasteboard.writeObjects(shots.map(item(for:)))
        }
    }

    /// Puts the screenshots at `urls` on the clipboard together, one item
    /// each, as the app's own write. Each is prepared off the main thread
    /// just before it goes and then let go: one picture in memory at a time,
    /// and the main thread only hands over one item at once. The first
    /// clears the clipboard, the next ones are added to it. Stops when the
    /// task is cancelled or something else wrote the clipboard meanwhile,
    /// so nothing is added to another copy. Answers how many went, 0 when
    /// none could be read (the clipboard is left as it was) or it stopped
    /// (the clipboard is someone else's).
    @MainActor
    static func copy(_ urls: [URL], to pasteboard: NSPasteboard) async -> Int {
        var written = 0
        var changeCount = 0
        for url in urls {
            guard !Task.isCancelled else { return 0 }
            guard let shot = await prepare(url) else { continue }
            // No suspension from here to the write.
            guard !Task.isCancelled else { return 0 }
            if written == 0 {
                write([shot], to: pasteboard)
            } else {
                guard pasteboard.changeCount == changeCount else { return 0 }
                pasteboard.writeObjects([item(for: shot)])
            }
            changeCount = pasteboard.changeCount
            written += 1
        }
        return written
    }
}
