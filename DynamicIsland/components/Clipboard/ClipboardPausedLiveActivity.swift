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

/// Closed-island indicator shown while clipboard history is paused, laid out
/// like the shelf indicator: [clipboard] ─── [ notch ] ─── [pause].
struct ClipboardPausedLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel

    private let sideWidth: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: sideWidth, alignment: .leading)

            Rectangle()
                .fill(Color.black)
                .frame(width: vm.closedNotchSize.width)

            Image(systemName: "pause.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
                .frame(width: sideWidth, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityLabel(Text("Clipboard history paused"))
    }
}
