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
import SwiftUI

/// Keyboard commands of the screenshot grid.
enum ScreenshotGridCommand: Equatable {
    case quickLook, selectAll, clearSelection, removeSelected, copy

    /// Space, Esc, Delete, ⌘A, ⌘C. Letters by character, so ⌘A/⌘C follow the
    /// layout like other apps; the rest by key code.
    init?(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        switch keyCode {
        case 49 where flags.isEmpty: self = .quickLook              // space
        case 53: self = .clearSelection                             // esc
        case 51, 117: self = .removeSelected                        // delete, forward delete
        default:
            guard flags == .command else { return nil }
            switch characters {
            case "a": self = .selectAll
            case "c": self = .copy
            default: return nil
            }
        }
    }

    init?(event: NSEvent) {
        self.init(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
    }
}

/// How a tile was clicked.
struct ScreenshotClick {
    /// Cmd-click: add to or remove from the selection.
    let extend: Bool
    /// Shift-click: select the range from the last clicked tile.
    let range: Bool
    /// Double-click: open it in Quick Look (it used to deselect it).
    var double = false
}

/// AppKit layer over a screenshot tile: clicks, multi-file drags and the grid
/// keys. SwiftUI's `.onDrag` carries one item, so dragging several files at
/// once needs an `NSDraggingSession` with one `NSDraggingItem` per file.
struct ScreenshotDragSource: NSViewRepresentable {
    let image: NSImage?
    let onClick: (ScreenshotClick) -> Void
    let urlsForDrag: () -> [URL]
    let onDragBegan: ([URL]) -> Void
    /// Called with whether the files were dropped somewhere (not cancelled).
    let onDragEnded: (Bool) -> Void
    let onCommand: (ScreenshotGridCommand) -> Void

    func makeNSView(context: Context) -> ScreenshotDragSourceView {
        let view = ScreenshotDragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ view: ScreenshotDragSourceView, context: Context) {
        update(view)
    }

    private func update(_ view: ScreenshotDragSourceView) {
        view.image = image
        view.onClick = onClick
        view.urlsForDrag = urlsForDrag
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
        view.onCommand = onCommand
    }
}

final class ScreenshotDragSourceView: NSView, NSDraggingSource {
    var image: NSImage?
    var onClick: ((ScreenshotClick) -> Void)?
    var urlsForDrag: (() -> [URL])?
    var onDragBegan: (([URL]) -> Void)?
    var onDragEnded: ((Bool) -> Void)?
    var onCommand: ((ScreenshotGridCommand) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private var draggedURLs: [URL] = []
    private let dragThreshold: CGFloat = 3

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let start = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        guard hypot(dx, dy) >= dragThreshold, let urls = urlsForDrag?(), !urls.isEmpty else { return }
        didStartDrag = true
        beginDrag(urls: urls, event: start)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !didStartDrag else { return }
        let flags = event.modifierFlags
        onClick?(ScreenshotClick(extend: flags.contains(.command), range: flags.contains(.shift), double: event.clickCount >= 2))
    }

    private func beginDrag(urls: [URL], event: NSEvent) {
        draggedURLs = urls
        let size = NSSize(width: 64, height: 44)
        let grabbed = image
        let items: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            // Fan the images out a little so several files read as several.
            let offset = CGFloat(min(index, 4)) * 6
            item.draggingFrame = NSRect(x: offset, y: -offset, width: size.width, height: size.height)
            // Asked for when AppKit draws the item, not all up front.
            item.imageComponentsProvider = {
                let component = NSDraggingImageComponent(key: .icon)
                component.contents = Self.dragImage(for: url, index: index, count: urls.count, grabbed: grabbed)
                component.frame = NSRect(origin: .zero, size: size)
                return [component]
            }
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    /// How many of several dragged files show their own thumbnail; each is
    /// a decode, and the pile shows about this many anyway.
    static let dragThumbnailLimit = 5

    /// Each dragged file shows its own picture: the grabbed tile's when it is
    /// the only one, a small thumbnail for the first few of several (all of
    /// them used to show the grabbed one), the file's icon after that.
    static func dragImage(for url: URL, index: Int, count: Int, grabbed: NSImage?) -> NSImage {
        if count == 1, let grabbed { return grabbed }
        if index < dragThumbnailLimit, let thumbnail = dragThumbnail(of: url) { return thumbnail }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func dragThumbnail(of url: URL, maxPixelSize: Int = 128) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy only: the originals stay in the screenshot folder.
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragBegan?(draggedURLs)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?(!operation.isEmpty)
        draggedURLs = []
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if let command = ScreenshotGridCommand(event: event) {
            onCommand?(command)
        } else {
            super.keyDown(with: event)
        }
    }

    /// Cmd+A and Cmd+C as key equivalents, while a screenshot tile has focus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard window?.firstResponder === self, flags == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "a": onCommand?(.selectAll)
        case "c": onCommand?(.copy)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func selectAll(_ sender: Any?) {
        onCommand?(.selectAll)
    }

    @objc func copy(_ sender: Any?) {
        onCommand?(.copy)
    }
}
