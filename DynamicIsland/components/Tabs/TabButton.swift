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

/// One island tab: a glyph in a 34 pt wide target (all tabs the same width),
/// the selected one on a soft fill. A dot inside the target says "new since
/// you last looked" (or, orange, that clipboard history is paused); it never
/// sticks out of the bar and gets cut off the way the old counts did.
struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    var badge: TabBadge? = nil
    var accent: Color? = nil
    let onClick: () -> Void

    var body: some View {
        DSIconButton(
            symbol: icon,
            label: helpText,
            isSelected: selected,
            width: 34,
            tint: selected ? accent : nil,
            dot: dotColor,
            action: onClick
        )
    }

    private var dotColor: Color? {
        switch badge {
        case .new: return DS.Palette.accent
        case .paused: return DS.Palette.paused
        case nil: return nil
        }
    }

    private var helpText: String {
        badge == .paused ? "\(label) — \(String(localized: "Clipboard history paused"))" : label
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
