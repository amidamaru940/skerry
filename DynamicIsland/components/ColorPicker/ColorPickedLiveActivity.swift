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

import SwiftUI

/// The closed island after a pick: the swatch on the left, the hex on the
/// right, for `ColorPickFlash.duration`. Both wings are as wide, so the
/// notch stays centred on the camera.
struct ColorPickedLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let color: PickedColor

    var body: some View {
        ColorPickedLiveActivityContent(
            color: color,
            notchWidth: vm.closedNotchSize.width,
            notchHeight: vm.effectiveClosedNotchHeight
        )
    }
}

/// The flash drawn from plain values.
struct ColorPickedLiveActivityContent: View {
    let color: PickedColor
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    static let wingWidth: CGFloat = 72

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(color.color)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: 16, height: 16)
                .frame(width: Self.wingWidth, alignment: .leading)
                .padding(.leading, 4)

            Rectangle()
                .fill(Color.black)
                .frame(width: notchWidth)

            Text(color.hexString)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.wingWidth, alignment: .trailing)
                .padding(.trailing, 4)
        }
        .frame(height: notchHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Picked color \(color.hexString), copied"))
    }
}
