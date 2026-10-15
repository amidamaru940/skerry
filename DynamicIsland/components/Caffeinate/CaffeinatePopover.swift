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

import Defaults
import SwiftUI

/// What the Keep Awake panel says (docs/PLAN-DESIGN.md §3.7).
enum KeepAwakeStatus {
    /// "Mac won't sleep for 14:55 more", "Mac stays awake", or off.
    static func title(isActive: Bool, remaining: TimeInterval?) -> String {
        guard isActive else { return String(localized: "Mac sleeps as usual") }
        guard let remaining else { return String(localized: "Mac stays awake") }
        return String(format: String(localized: "Mac won't sleep for %@ more"), CaffeinateManager.remainingLabel(remaining))
    }

    /// Choosing the duration that is already running changes nothing (it
    /// used to restart the countdown).
    static func shouldStart(_ duration: CaffeinateDuration, isActive: Bool, active: CaffeinateDuration?) -> Bool {
        !(isActive && active == duration)
    }
}

/// Keep Awake: the state in large type, the durations as one segmented
/// row, and a filled "Turn Off" while it is on.
struct CaffeinatePopover: View {
    @ObservedObject private var caffeinateManager = CaffeinateManager.shared
    @Default(.caffeinateKeepsDisplayAwake) private var keepsDisplayAwake
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: caffeinateManager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(caffeinateManager.isActive ? DS.Palette.attention : DS.Palette.textTertiary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(KeepAwakeStatus.title(isActive: caffeinateManager.isActive, remaining: caffeinateManager.remainingTime))
                        .font(DS.Typeface.title)
                        .foregroundStyle(DS.Palette.text)
                        // A countdown must not reflow the panel every second.
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if caffeinateManager.isActive {
                        Group {
                            if keepsDisplayAwake {
                                Text("The display stays on too")
                            } else {
                                Text("The display may still turn off")
                            }
                        }
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(CaffeinateDuration.panelOrder) { duration in
                    durationSegment(duration)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.card))

            if failed {
                Label("macOS did not allow it. Try again.", systemImage: "exclamationmark.triangle")
                    .font(DS.Typeface.caption)
                    .foregroundStyle(DS.Palette.attention)
            }

            if caffeinateManager.isActive {
                Button {
                    withAnimation(DS.spring) { caffeinateManager.deactivate() }
                } label: {
                    Text("Turn Off").frame(maxWidth: .infinity)
                }
                .buttonStyle(DSButtonStyle(kind: .primary, height: 32))
            } else {
                Text("Choose how long the Mac should stay awake.")
                    .font(DS.Typeface.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .padding(16)
        .frame(width: DS.panelWidth)
    }

    private func durationSegment(_ duration: CaffeinateDuration) -> some View {
        let isOn = caffeinateManager.isActive && caffeinateManager.activeDuration == duration
        return Button {
            guard KeepAwakeStatus.shouldStart(duration, isActive: caffeinateManager.isActive, active: caffeinateManager.activeDuration) else { return }
            withAnimation(DS.spring) {
                failed = !caffeinateManager.activate(for: duration)
            }
        } label: {
            Text(duration.shortName)
                .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? Color.black : DS.Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(isOn ? DS.Palette.attention : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(duration.displayName)
        .accessibilityLabel(Text(duration.displayName))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    CaffeinatePopover()
}
