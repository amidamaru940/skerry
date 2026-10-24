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

/// The open island on a screen with a camera notch keeps the menu bar to the
/// app in front (owner, 22.10.2026: its header hid Chrome's «Вкладки»,
/// «Окно», «Справка»). In the menu bar it is only a neck as wide as the
/// closed island, around the camera; the panel, header first, hangs from the
/// bottom of the menu bar and flows out of the neck with the open flares.
///
/// Beside the neck the island's window is fully transparent (no fill, no
/// shadow), and a transparent pixel passes its click to the menu bar below,
/// so the titles there stay visible and clickable. Hover and the "pointer
/// is inside" checks leave that band out as well.
enum OpenIslandNeck {
    /// How much taller than the notch the menu bar is taken to be at most.
    static let maxMenuBarExcess: CGFloat = 8

    /// The menu-bar band the open island leaves to the menus: the notch's
    /// height (the safe-area top inset), or the menu bar's when that is a
    /// little taller (33 against 32 on the 14"), so the panel starts where
    /// the menu bar ends. A hidden menu bar measures 0 and leaves the notch.
    /// 0 without a notch: there the open island keeps its header in the top
    /// band, as before.
    static func bandHeight(safeAreaTop: CGFloat, menuBarHeight: CGFloat) -> CGFloat {
        guard safeAreaTop > 0 else { return 0 }
        return max(safeAreaTop, min(menuBarHeight, safeAreaTop + maxMenuBarExcess))
    }

    static func bandHeight(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 0 }
        return bandHeight(
            safeAreaTop: screen.safeAreaInsets.top,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
    }

    /// The band on the screen named `name` (the main screen for nil; none
    /// for a name no screen has, as the island treats it). The Dynamic Island
    /// pill is only ever drawn on screens without a notch.
    static func bandHeight(forScreenNamed name: String?) -> CGFloat {
        guard !shouldUseDynamicIslandMode(for: name) else { return 0 }
        guard let name else { return bandHeight(for: NSScreen.main) }
        return bandHeight(for: NSScreen.screens.first { $0.localizedName == name })
    }

    /// The neck's body: the camera, exactly the closed island's at rest.
    static func bodyWidth(closedNotchWidth: CGFloat) -> CGFloat {
        ClosedWingE.cameraWidth(closedNotchWidth: closedNotchWidth)
    }

    /// The neck at the screen edge, its closed flares included: the camera
    /// plus the closed flare either side, as wide as the closed island at
    /// rest.
    static func outerWidth(closedNotchWidth: CGFloat) -> CGFloat {
        bodyWidth(closedNotchWidth: closedNotchWidth) + 2 * cornerRadiusInsets.closed.top
    }

    /// The neck `NotchShape` draws, or nil without a band. `topInset` is how
    /// far the shape's rect starts above the screen edge (the hit shape spans
    /// the window's top bleed as well). Closed, the same neck with `blend` 0:
    /// the classic shape, and the open morph only has to move `blend`.
    static func neck(
        closedNotchWidth: CGFloat,
        bandHeight: CGFloat,
        isOpen: Bool,
        topInset: CGFloat = 0
    ) -> NotchShape.Neck? {
        guard bandHeight > 0 else { return nil }
        return NotchShape.Neck(
            blend: isOpen ? 1 : 0,
            width: bodyWidth(closedNotchWidth: closedNotchWidth),
            height: bandHeight + topInset,
            flare: cornerRadiusInsets.closed.top
        )
    }

    /// Whether `point` (global, y up) is in the menu bar beside the neck:
    /// inside the island's window, but the menus', not the island's.
    static func isBesideNeck(
        _ point: CGPoint,
        screenFrame: CGRect,
        bandHeight: CGFloat,
        neckOuterWidth: CGFloat
    ) -> Bool {
        guard bandHeight > 0, point.y >= screenFrame.maxY - bandHeight else { return false }
        return abs(point.x - screenFrame.midX) > neckOuterWidth / 2
    }

    /// Whether `point` (global, y up) is on the island's window as the island
    /// takes it: the window's frame, its top pixel included, less the band
    /// beside the neck. `footprint`, the closed island the island was opened
    /// from (where the pointer may still rest), is the island's in the band.
    static func windowContains(
        _ point: CGPoint,
        windowFrame: CGRect,
        screenFrame: CGRect,
        bandHeight: CGFloat,
        neckOuterWidth: CGFloat,
        footprint: CGRect? = nil
    ) -> Bool {
        guard IslandHoverZone.contains(windowFrame, point) else { return false }
        guard isBesideNeck(point, screenFrame: screenFrame, bandHeight: bandHeight, neckOuterWidth: neckOuterWidth) else {
            return true
        }
        return footprint.map { IslandHoverZone.contains($0, point) } ?? false
    }

    /// The island window's size on a screen for the island's `base` size:
    /// the Dynamic Island pill's shadow and top insets, or, in the notch
    /// style, the top bleed plus the band (0 without a notch), which stays in
    /// the window while closed too, transparent, so opening never has to
    /// wait for the window to grow.
    static func windowSize(
        for base: CGSize,
        dynamicIslandMode: Bool,
        topBleed: CGFloat,
        bandHeight: CGFloat
    ) -> CGSize {
        var adjusted = base
        if dynamicIslandMode {
            adjusted.width += dynamicIslandShadowInset * 2
            adjusted.height += dynamicIslandTopOffset
        } else {
            adjusted.height += topBleed + bandHeight
        }
        return adjusted
    }
}
