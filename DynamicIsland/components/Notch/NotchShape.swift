/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import SwiftUI

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat
    private var neck: Neck

    /// The open island on a screen with a notch (`OpenIslandNeck`): in the
    /// menu bar only a neck as wide as the closed island, the panel below.
    struct Neck: Equatable {
        /// 0 draws the classic shape, 1 the neck and the panel; in between
        /// the neck pinches in from the panel's width while the island opens
        /// (it is the one value the open/close spring moves for the neck).
        var blend: CGFloat
        /// The neck's body: the camera, as the closed island at rest.
        var width: CGFloat
        /// The menu-bar band, from the top of the shape's rect.
        var height: CGFloat
        /// The flare where the neck meets the screen edge (the closed one).
        var flare: CGFloat

        static let none = Neck(blend: 0, width: 0, height: 0, flare: 0)
    }

    /// Where the parts of the necked shape lie in `rect` (y down).
    struct NeckLayout: Equatable {
        var neckLeft: CGFloat
        var neckRight: CGFloat
        /// The flare at the screen edge, outside each neck side.
        var neckFlare: CGFloat
        /// The concave flare where the neck flows out into the panel.
        var junctionFlare: CGFloat
        var panelTop: CGFloat
        var panelLeft: CGFloat
        var panelRight: CGFloat
        /// The panel's outer top corners.
        var panelCornerRadius: CGFloat
        var bottomCornerRadius: CGFloat
    }

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil,
        neck: Neck? = nil
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
        self.neck = neck ?? .none
    }

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            .init(
                .init(topCornerRadius, bottomCornerRadius),
                .init(.init(neck.blend, neck.width), .init(neck.height, neck.flare))
            )
        }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            neck = Neck(
                blend: newValue.second.first.first,
                width: newValue.second.first.second,
                height: newValue.second.second.first,
                flare: newValue.second.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        guard neck.blend > 0 else { return classicPath(in: rect) }
        return neckedPath(Self.neckLayout(
            in: rect,
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius,
            neck: neck
        ), in: rect)
    }

    /// The necked shape's geometry. The panel keeps the classic body's sides
    /// (`topCornerRadius` in from the rect, so the content keeps its inset)
    /// and hangs from the bottom of the band; the neck is centred, flares
    /// into the screen edge with the closed flare and into the panel with
    /// the open one (`topCornerRadius`). With `blend` 0 it is the classic
    /// shape; while the rect is still small (mid-animation) the panel moves
    /// up and every radius shrinks to what fits.
    static func neckLayout(
        in rect: CGRect,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        neck: Neck
    ) -> NeckLayout {
        let blend = min(max(neck.blend, 0), 1)
        let t = max(0, topCornerRadius)
        let panelLeft = rect.minX + t
        let panelRight = max(panelLeft, rect.maxX - t)
        let panelHalf = (panelRight - panelLeft) / 2
        let targetHalf = min(max(0, neck.width) / 2, panelHalf)
        // The neck pinches in early (ease-out), so the panel is seen growing
        // out of a neck already about the camera's width.
        let pinch = 1 - pow(1 - blend, 3)
        let neckHalf = panelHalf + (targetHalf - panelHalf) * pinch
        let gap = max(0, panelHalf - neckHalf)

        var flare = t + (max(0, neck.flare) - t) * blend
        var junction = min(t, gap / 2)
        var corner = min(max(0, bottomCornerRadius), gap / 2)
        var bottom = max(0, bottomCornerRadius)
        // The neck's two flares and the panel's two corners share the height.
        let needed = flare + junction + corner + bottom
        if needed > rect.height, needed > 0 {
            let scale = max(0, rect.height) / needed
            flare *= scale
            junction *= scale
            corner *= scale
            bottom *= scale
        }
        let panelTop = min(
            max(rect.minY + flare + junction, rect.minY + max(0, neck.height)),
            rect.maxY - corner - bottom
        )
        return NeckLayout(
            neckLeft: rect.midX - neckHalf,
            neckRight: rect.midX + neckHalf,
            neckFlare: flare,
            junctionFlare: junction,
            panelTop: panelTop,
            panelLeft: panelLeft,
            panelRight: panelRight,
            panelCornerRadius: corner,
            bottomCornerRadius: bottom
        )
    }

    private func neckedPath(_ l: NeckLayout, in rect: CGRect) -> Path {
        var path = Path()
        // The neck's left side, from its flare at the screen edge.
        path.move(to: CGPoint(x: l.neckLeft - l.neckFlare, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: l.neckLeft, y: rect.minY + l.neckFlare),
            control: CGPoint(x: l.neckLeft, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: l.neckLeft, y: l.panelTop - l.junctionFlare))
        // Out into the panel, along its top edge, round its top-left corner.
        if l.junctionFlare > 0 {
            path.addQuadCurve(
                to: CGPoint(x: l.neckLeft - l.junctionFlare, y: l.panelTop),
                control: CGPoint(x: l.neckLeft, y: l.panelTop)
            )
        }
        path.addLine(to: CGPoint(x: l.panelLeft + l.panelCornerRadius, y: l.panelTop))
        if l.panelCornerRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: l.panelLeft, y: l.panelTop + l.panelCornerRadius),
                control: CGPoint(x: l.panelLeft, y: l.panelTop)
            )
        }
        // Down the panel and along its bottom, as the classic body.
        path.addLine(to: CGPoint(x: l.panelLeft, y: rect.maxY - l.bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: l.panelLeft + l.bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: l.panelLeft, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: l.panelRight - l.bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: l.panelRight, y: rect.maxY - l.bottomCornerRadius),
            control: CGPoint(x: l.panelRight, y: rect.maxY)
        )
        // Up the right side, back into the neck and up to the screen edge.
        path.addLine(to: CGPoint(x: l.panelRight, y: l.panelTop + l.panelCornerRadius))
        if l.panelCornerRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: l.panelRight - l.panelCornerRadius, y: l.panelTop),
                control: CGPoint(x: l.panelRight, y: l.panelTop)
            )
        }
        path.addLine(to: CGPoint(x: l.neckRight + l.junctionFlare, y: l.panelTop))
        if l.junctionFlare > 0 {
            path.addQuadCurve(
                to: CGPoint(x: l.neckRight, y: l.panelTop - l.junctionFlare),
                control: CGPoint(x: l.neckRight, y: l.panelTop)
            )
        }
        path.addLine(to: CGPoint(x: l.neckRight, y: rect.minY + l.neckFlare))
        path.addQuadCurve(
            to: CGPoint(x: l.neckRight + l.neckFlare, y: rect.minY),
            control: CGPoint(x: l.neckRight, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }

    private func classicPath(in rect: CGRect) -> Path {
        var path = Path()

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY + topCornerRadius
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius + bottomCornerRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius - bottomCornerRadius,
                y: rect.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY + topCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        return path
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
