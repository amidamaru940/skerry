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
import UniformTypeIdentifiers

/// A clipboard picture being dragged out: the PNG itself for apps that take
/// pictures (chats, Mail), and a file promise for Finder and other folders, so
/// the file is written only where the picture was dropped. No temporary copy
/// is made anywhere.
final class ClipboardImagePromiseProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let pngData: Data
    let fileName: String

    init(pngData: Data, fileName: String) {
        self.pngData = pngData
        self.fileName = fileName
        super.init()
        fileType = UTType.png.identifier
        delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.png] + super.writableTypes(for: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .png ? pngData : super.pasteboardPropertyList(forType: type)
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        fileName
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        do {
            try pngData.write(to: url, options: .atomic)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

enum ClipboardDragWriters {
    /// One pasteboard writer per dragged thing: several for a multi-file entry.
    static func writers(for item: ClipboardItem, now: Date = Date()) -> [NSPasteboardWriting] {
        switch item.type {
        case .image:
            guard let data = item.getImageData() else { return [] }
            // Already PNG (screenshots, most copies): hand it over unchanged.
            let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
            let png = isPNG ? data : (NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) ?? data)
            let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: ".")
            return [ClipboardImagePromiseProvider(pngData: png, fileName: "Clipboard Image \(stamp).png")]
        case .file:
            return (item.fileURLs ?? []).compactMap { URL(string: $0) as NSURL? }
        case .url:
            guard let text = item.stringData else { return [] }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(text, forType: .string)
            if let url = URL(string: text) { pasteboardItem.setString(url.absoluteString, forType: .URL) }
            return [pasteboardItem]
        case .rtf, .text, .unknown:
            guard let text = item.stringData else { return [] }
            let pasteboardItem = NSPasteboardItem()
            if item.type == .rtf, let rtf = item.rtfData { pasteboardItem.setData(rtf, forType: .rtf) }
            pasteboardItem.setString(text, forType: .string)
            return [pasteboardItem]
        }
    }
}

/// Upstream's image drag copied the PNG to the shared temporary folder as
/// `clipboard_image_<UUID>.png` and never removed it. Those copies are deleted
/// at launch; nothing new is written there.
enum ClipboardTemporaryFiles {
    static func removeLegacyDragCopies(in directory: URL = FileManager.default.temporaryDirectory) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix("clipboard_image_") && name.hasSuffix(".png") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
