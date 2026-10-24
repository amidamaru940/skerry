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

extension NSWindow {
    /// Shows `host` (a hosting view) in a window Skerry sizes itself, inside
    /// a plain container view. As the window's own contentView in a SwiftUI
    /// app, a hosting view gets SwiftUI's window-sizing helper whatever its
    /// `sizingOptions`: it grew the island from `windowDidLayout` while
    /// Skerry set the frame too, and the two re-entered Update Constraints
    /// until AppKit threw (crashes 23.10, 09:53 and 10:20, as screenshots
    /// came into the open «Буфер»).
    func setSelfSizedContent(_ host: NSView) {
        let container = FillingContainerView(frame: NSRect(origin: .zero, size: contentRect(forFrameRect: frame).size))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = container.bounds
        container.addSubview(host)
        contentView = container
    }
}

/// Keeps its subviews at its own size. Autoresizing does not: from a zero
/// size (the picture preview panel starts at .zero) it left the preview at
/// 0 × 0.
private final class FillingContainerView: NSView {
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        fill()
    }

    override func layout() {
        super.layout()
        fill()
    }

    private func fill() {
        for subview in subviews where subview.frame != bounds {
            subview.frame = bounds
        }
    }
}
