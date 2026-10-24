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
import ImageIO

/// Tells a screenshot taken to the clipboard (⌃⇧⌘3/4/5) from any other
/// copied picture.
///
/// The pasteboard carries no marker: checked on macOS 26.6, a clipboard
/// screenshot is one item of `public.png` (plus the TIFF and legacy names the
/// pasteboard adds), exactly like a picture copied in any app. What does
/// differ is timing: the system screenshot tools (`screencapture`,
/// `screencaptureui`) are not running at rest, start for the capture and quit
/// about five seconds after writing the clipboard. So a picture-only clipboard
/// change while one of them runs is a screenshot.
enum ClipboardScreenshotDetector {
    static let toolProcessNames: Set<String> = ["screencapture", "screencaptureui"]

    /// Whether a screenshot tool runs right now. Replaced in tests.
    static var isScreenshotToolRunning: () -> Bool = {
        !RunningProcesses.names().isDisjoint(with: toolProcessNames)
    }

    private static let imageTypes: Set<NSPasteboard.PasteboardType> = [.png, .tiff, .init("public.jpeg")]
    private static let disqualifyingTypes: Set<NSPasteboard.PasteboardType> = [
        .string, .rtf, .rtfd, .html, .fileURL, .URL,
        .init("NSFilenamesPboardType"), .init("public.url"), .init("public.utf8-plain-text"),
    ]

    /// A picture with no text, link, rich text or file alongside it.
    static func holdsOnlyAPicture(_ pasteboard: NSPasteboard) -> Bool {
        let types = Set(ClipboardCapturePolicy.allTypes(on: pasteboard))
        return !types.isDisjoint(with: imageTypes) && types.isDisjoint(with: disqualifyingTypes)
    }

    static func isScreenshot(_ pasteboard: NSPasteboard) -> Bool {
        holdsOnlyAPicture(pasteboard) && looksTaken(pasteboard)
    }

    /// The second sign, checked live on 15.10: a full-screen screenshot to
    /// the clipboard (⌃⇧⌘3) starts no screenshot tool the app could see,
    /// but its picture is exactly one display in pixels (3456 × 2234 on the
    /// owner's MacBook). A copied picture of exactly that size is rare.
    static func looksTaken(_ pasteboard: NSPasteboard) -> Bool {
        isScreenshotToolRunning() || isFullScreenPicture(pasteboard)
    }

    /// Pixel sizes of the connected displays. Replaced in tests.
    static var screenPixelSizes: () -> [CGSize] = {
        NSScreen.screens.map {
            CGSize(width: ($0.frame.width * $0.backingScaleFactor).rounded(),
                   height: ($0.frame.height * $0.backingScaleFactor).rounded())
        }
    }

    static func isFullScreenPicture(_ pasteboard: NSPasteboard) -> Bool {
        guard let size = pixelSize(of: pasteboard) else { return false }
        return screenPixelSizes().contains(size)
    }

    /// The picture's size from its header, without decoding it.
    static func pixelSize(of pasteboard: NSPasteboard) -> CGSize? {
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }

    /// While on, clipboard screenshots go to the Screenshots tab and not to
    /// the clipboard history; while off, they are ordinary clipboard pictures.
    static var routesToScreenshots: Bool {
        Defaults[.enableScreenshotShelf] && Defaults[.collectClipboardScreenshots]
    }
}

/// To the person, screenshots are one feature: saved to a file or taken to
/// the clipboard, they gather in the same batches (owner, 22.10: «временных
/// скринов нету, а они самые важные»). The keys stay separate, so Settings
/// can still offer the clipboard part on its own, but the «Скриншоты» switch
/// of the onboarding and of Settings turns both on or off.
enum ScreenshotFeature {
    static func setEnabled(_ on: Bool) {
        Defaults[.enableScreenshotShelf] = on
        Defaults[.collectClipboardScreenshots] = on
    }
}
