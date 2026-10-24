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
import SwiftUI

/// Closed-island indicator while Keep Awake is on, so it is visible without
/// opening the island: [cup] ─── [ notch ] ─── [time left or ∞].
/// Both wings are the same width, so the island stays centred on the notch.
struct KeepAwakeLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var caffeinate = CaffeinateManager.shared

    static func label(remaining: TimeInterval?) -> String {
        remaining.map(CaffeinateManager.remainingLabel) ?? "∞"
    }

    /// Wide enough for the label in 12 pt monospaced digits.
    static func wingWidth(for label: String) -> CGFloat {
        max(26, CGFloat(label.count) * 7.5 + 4)
    }

    /// 12 pt semibold, tabular digits: the time left.
    static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    /// The cup flush left, the time flush right, in equal wings.
    static func closedGeometry(closedNotchWidth: CGFloat, label: String) -> ClosedWingGeometry {
        let wing = wingWidth(for: label)
        return ClosedWingGeometry(
            leadingWing: wing,
            middle: closedNotchWidth,
            trailingWing: wing,
            leadingContent: 0,
            trailingContent: ClosedWingE.measure(label, font: labelFont),
            camera: ClosedWingE.cameraWidth(closedNotchWidth: closedNotchWidth)
        )
    }

    var body: some View {
        let label = Self.label(remaining: caffeinate.remainingTime)
        let wing = Self.wingWidth(for: label)
        HStack(spacing: 0) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.attention)
                .frame(width: wing, alignment: .leading)

            Rectangle()
                .fill(Color.black)
                .frame(width: vm.closedNotchSize.width)

            Text(label)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(DS.Palette.attention)
                .lineLimit(1)
                .frame(width: wing, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Keep Awake"))
        .accessibilityValue(Text(label))
    }
}
