/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

/// Shown for a moment in the closed island when files land on the shelf
/// (the shelf no longer sits there the whole time):
///   [tray icon] ─── [ notch ] ─── [+N]
struct ShelfInlineLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var flash = ShelfFlashModel.shared

    private let sideWidth: CGFloat = 26

    var body: some View {
        let added = flash.flash?.added ?? 0
        HStack(spacing: 0) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.text)
                .frame(width: sideWidth, alignment: .leading)

            Rectangle()
                .fill(Color.black)
                .frame(width: vm.closedNotchSize.width)

            Text("+\(added)")
                .font(.system(.callout, design: .rounded, weight: .bold))
                .foregroundStyle(DS.Palette.text)
                .contentTransition(.numericText(countsDown: false))
                .animation(.smooth(duration: 0.3), value: added)
                .frame(width: sideWidth, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Added to the shelf: \(added)"))
    }
}
