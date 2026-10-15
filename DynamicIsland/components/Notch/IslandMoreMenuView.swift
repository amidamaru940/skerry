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

import Defaults
import SwiftUI

/// The popover of the "…" button: a short menu, and in its place the panel
/// an entry opens (Keep Awake, colour picker, clipboard, app volume),
/// with a way back to the menu.
struct IslandMoreMenuView: View {
    @Binding var panel: IslandMoreMenu.Panel
    @Binding var isPresented: Bool
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var caffeinate = CaffeinateManager.shared
    @Default(.enableCaffeinate) private var enableCaffeinate
    @Default(.enableColorPickerFeature) private var enableColorPicker
    @Default(.enableClipboardManager) private var enableClipboard
    @Default(.clipboardDisplayMode) private var clipboardDisplayMode
    @Default(.clipboardHistoryPaused) private var clipboardPaused
    @Default(.enablePerAppVolume) private var enableAppVolume
    @Default(.showMirror) private var showMirror

    private var features: IslandMoreMenu.Features {
        IslandMoreMenu.Features(
            keepAwake: enableCaffeinate,
            colorPicker: enableColorPicker,
            clipboard: enableClipboard,
            clipboardOutsideTabs: clipboardDisplayMode != .notchTab || !NotchTabLayout.isVisible(.clipboard),
            clipboardPaused: clipboardPaused,
            appVolume: enableAppVolume,
            mirror: showMirror
        )
    }

    var body: some View {
        Group {
            if panel == .menu {
                menu
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(DS.spring) { panel = .menu }
                    } label: {
                        Label(String(localized: "Back"), systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    panelContent
                }
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 2) {
            ForEach(Array(IslandMoreMenu.entries(for: features).enumerated()), id: \.offset) { _, entry in
                if entry == .settings {
                    Divider().padding(.vertical, 4).padding(.horizontal, 8)
                }
                MoreMenuRow(
                    symbol: symbol(for: entry),
                    title: title(for: entry),
                    trailing: trailing(for: entry),
                    trailingTint: entry == .keepAwake ? DS.Palette.attention : DS.Palette.textTertiary,
                    opensPanel: IslandMoreMenu.panel(for: entry) != nil
                ) {
                    act(on: entry)
                }
            }
        }
        .padding(6)
        .frame(width: DS.panelWidth)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .keepAwake: CaffeinatePopover()
        case .colorPicker: ColorPickerPopover()
        case .clipboard: ClipboardPopover()
        case .appVolume: PerAppVolumePopover()
        case .menu: EmptyView()
        }
    }

    private func act(on entry: IslandMoreMenu.Entry) {
        switch entry {
        case .colorPicker where Defaults[.colorPickerDisplayMode] == .panel:
            isPresented = false
            ColorPickerPanelManager.shared.toggleColorPickerPanel()
        case .clipboard where clipboardDisplayMode == .panel:
            isPresented = false
            ClipboardPanelManager.shared.toggleClipboardPanel()
        case .clipboard where clipboardDisplayMode == .separateTab:
            isPresented = false
            DynamicIslandViewCoordinator.shared.currentView = .notes
        case .clipboardPause:
            clipboardPaused.toggle()
        case .mirror:
            isPresented = false
            vm.toggleCameraPreview()
        case .settings:
            isPresented = false
            SettingsWindowController.shared.showWindow()
        default:
            if let next = IslandMoreMenu.panel(for: entry) {
                withAnimation(DS.spring) { panel = next }
            }
        }
    }

    private func symbol(for entry: IslandMoreMenu.Entry) -> String {
        switch entry {
        case .keepAwake: return caffeinate.isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        case .colorPicker: return "eyedropper"
        case .clipboard: return "doc.on.clipboard"
        case .clipboardPause(let paused): return paused ? "play.circle" : "pause.circle"
        case .appVolume: return "slider.vertical.3"
        case .mirror: return "web.camera"
        case .settings: return "gearshape"
        }
    }

    private func title(for entry: IslandMoreMenu.Entry) -> String {
        switch entry {
        case .keepAwake: return String(localized: "Keep Awake")
        case .colorPicker: return String(localized: "Color Picker")
        case .clipboard: return String(localized: "Clipboard")
        case .clipboardPause(let paused):
            return paused ? String(localized: "Resume clipboard history") : String(localized: "Pause clipboard history")
        case .appVolume: return String(localized: "App Volume")
        case .mirror: return String(localized: "Mirror")
        case .settings: return String(localized: "Settings…")
        }
    }

    private func trailing(for entry: IslandMoreMenu.Entry) -> String? {
        switch entry {
        case .keepAwake:
            guard caffeinate.isActive else { return nil }
            return caffeinate.remainingTime.map(CaffeinateManager.remainingLabel) ?? "∞"
        case .settings:
            return "⌘,"
        default:
            return nil
        }
    }
}

struct MoreMenuRow: View {
    let symbol: String
    let title: String
    let trailing: String?
    let trailingTint: Color
    let opensPanel: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(trailingTint)
                }
                if opensPanel {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(isHovering ? DS.Palette.hoverFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
    }
}

/// The capsule at the right of the header: live states only (recording,
/// Keep Awake time, Focus, low battery); nothing when nothing is going on.
struct IslandStatusCapsule: View {
    var onKeepAwakeTap: () -> Void = {}
    @ObservedObject private var caffeinate = CaffeinateManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @ObservedObject private var doNotDisturb = DoNotDisturbManager.shared
    @ObservedObject private var recording = ScreenRecordingManager.shared
    @Default(.showBatteryIndicator) private var showBattery

    private var items: [IslandStatus.Item] {
        IslandStatus.items(
            recording: Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] && recording.isRecording,
            keepAwake: caffeinate.isActive,
            keepAwakeRemaining: caffeinate.remainingTime,
            focus: Defaults[.enableDoNotDisturbDetection] && Defaults[.showDoNotDisturbIndicator] && doNotDisturb.isDoNotDisturbActive,
            batteryPercent: showBattery ? battery.levelBattery : nil,
            charging: battery.isCharging || battery.isPluggedIn
        )
    }

    var body: some View {
        let items = items
        if !items.isEmpty {
            Button(action: onKeepAwakeTap) {
                DSStatusCapsule {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        view(for: item)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!items.contains { if case .keepAwake = $0 { return true } else { return false } })
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder
    private func view(for item: IslandStatus.Item) -> some View {
        switch item {
        case .recording:
            Circle().fill(DS.Palette.danger).frame(width: 7, height: 7)
                .accessibilityLabel(Text("Screen recording"))
        case .keepAwake(let remaining):
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer.fill")
                Text(remaining.map(CaffeinateManager.remainingLabel) ?? "∞").monospacedDigit()
            }
            .foregroundStyle(DS.Palette.attention)
            .help(String(localized: "Keep Awake"))
        case .focus:
            Image(systemName: "moon.fill")
                .foregroundStyle(Color(rgb: 0x5E5CE6))
                .accessibilityLabel(Text("Focus"))
        case .lowBattery(let percent):
            HStack(spacing: 3) {
                Image(systemName: "battery.25percent")
                Text("\(percent)%").monospacedDigit()
            }
            .foregroundStyle(DS.Palette.danger)
        }
    }
}
