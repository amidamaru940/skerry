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
    @Default(.enableLyrics) private var enableLyrics
    @ObservedObject private var playerOverflow = PlayerOverflow.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var clipboard = ClipboardManager.shared
    @ObservedObject private var buffer = BufferTabState.shared
    @ObservedObject private var presentation = ScreenPresentation.shared
    @ObservedObject private var shots = ScreenshotShelfManager.shared
    @Default(.enableScreenshotShelf) private var enableScreenshots

    /// «Буфер» with its history: Settings opens on the clipboard page
    /// (Buffer v3: the tab's own «…» is gone).
    private var onClipboardHistory: Bool {
        coordinator.currentView == .clipboard && clipboardDisplayMode == .notchTab
    }

    /// The history itself on screen, with room for its «Отменить» line:
    /// only then is «Очистить историю» offered (never on «Снимки» or while
    /// the screen is shared, where a clear went by unseen).
    private var offersClearHistory: Bool {
        guard onClipboardHistory else { return false }
        return BufferLayout.offersClearHistory(segment: shownSegment, hidingContent: presentation.isHidingContent)
    }

    /// The filter «Буфер» shows.
    private var shownSegment: BufferSegment? {
        let available = BufferSegment.available(clipboard: enableClipboard, screenshots: enableScreenshots)
        return BufferSegment.resolve(buffer.segment, available: available)
    }

    /// What «Очистить» would take there: the filter's copies and, on «Все»
    /// and «Снимки», the screenshots shown.
    private var clearableCount: Int {
        BufferTabState.clearableCount(shownSegment, history: clipboard.clipboardHistory, shownShots: enableScreenshots ? shots.shownItemIDs.count : 0)
    }

    private var features: IslandMoreMenu.Features {
        IslandMoreMenu.Features(
            keepAwake: enableCaffeinate,
            colorPicker: enableColorPicker,
            clipboard: enableClipboard,
            clipboardOutsideTabs: clipboardDisplayMode != .notchTab || !NotchTabLayout.isVisible(.clipboard),
            clipboardPaused: clipboardPaused,
            appVolume: enableAppVolume,
            mirror: showMirror,
            player: playerOverflow.buttons,
            clipboardHistoryCount: offersClearHistory ? clearableCount : nil
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
                        // «‹ Назад»: 28 high, the chevron at the panel edge + 16.
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(DSE.Typeface.caption)
                            Text(String(localized: "Back"))
                                .eText(.body)
                        }
                        .foregroundStyle(DSE.Palette.textSecondary)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressDimStyle())
                    panelContent
                }
            }
        }
        // E: every island menu is black (VISUAL-E §2.11); the popover's own
        // frame stays the system's.
        .background(DSE.Palette.island)
        .presentationBackground(DSE.Palette.island)
    }

    /// 8 + 28 × rows + 9 × dividers; rows inset 4, text only.
    private var menu: some View {
        VStack(spacing: 0) {
            let entries = IslandMoreMenu.entries(for: features)
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                if IslandMoreMenu.startsSection(entries, at: index) {
                    Hairline()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                MoreMenuRow(
                    title: title(for: entry),
                    trailing: trailing(for: entry),
                    opensPanel: IslandMoreMenu.panel(for: entry) != nil
                ) {
                    act(on: entry)
                }
                .disabled(isDisabled(entry))
            }
        }
        .padding(4)
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
        case .clearClipboardHistory:
            isPresented = false
            // Looked at again: the filter or the screen may have changed
            // while the menu was open.
            if offersClearHistory, let segment = shownSegment { BufferTabState.shared.clear(segment) }
        case .settings:
            isPresented = false
            if enableClipboard && onClipboardHistory {
                SettingsWindowController.shared.showWindow(page: SettingsWindowController.clipboardPage)
            } else {
                SettingsWindowController.shared.showWindow()
            }
        case .player(.repeatMode):
            // The menu stays, so the new mode shows in the row.
            MusicManager.shared.toggleRepeat()
        case .player(.likeTrack):
            MusicManager.shared.toggleLike()
        case .player(.lyrics):
            // Turning lyrics on asks first; the menu goes before the question.
            isPresented = false
            DispatchQueue.main.async { LyricsConsent.toggle() }
        default:
            if let next = IslandMoreMenu.panel(for: entry) {
                withAnimation(DS.spring) { panel = next }
            }
        }
    }

    private func title(for entry: IslandMoreMenu.Entry) -> String {
        switch entry {
        case .clearClipboardHistory: return String(localized: "Clear")
        case .keepAwake: return String(localized: "Keep Awake")
        case .colorPicker: return String(localized: "Color Picker")
        case .clipboard: return String(localized: "Clipboard")
        case .clipboardPause(let paused):
            return paused ? String(localized: "Resume clipboard history") : String(localized: "Pause clipboard history")
        case .appVolume: return String(localized: "App Volume")
        case .mirror: return String(localized: "Mirror")
        case .player(.repeatMode): return String(localized: "Repeat")
        case .player(.lyrics):
            return enableLyrics ? String(localized: "Hide Lyrics") : String(localized: "Show Lyrics")
        case .player(.likeTrack):
            return musicManager.isCurrentTrackLiked == true
                ? String(localized: "Remove from Favorites")
                : String(localized: "Favorite Song")
        case .player: return ""
        case .settings: return String(localized: "Settings…")
        }
    }

    /// Favourite waits for the liked state, and a read-only source cannot change it.
    private func isDisabled(_ entry: IslandMoreMenu.Entry) -> Bool {
        if case .clearClipboardHistory(let count) = entry { return count == 0 }
        guard entry == .player(.likeTrack) else { return false }
        return LikeTrackPresentation(
            isCurrentTrackLiked: musicManager.isCurrentTrackLiked,
            isReadOnly: musicManager.activeSourceFavoritingIsReadOnly
        ).isDisabled
    }

    private func trailing(for entry: IslandMoreMenu.Entry) -> String? {
        switch entry {
        case .keepAwake:
            guard caffeinate.isActive else { return nil }
            return caffeinate.remainingTime.map(CaffeinateManager.remainingLabel) ?? "∞"
        case .settings:
            return "⌘,"
        case .clearClipboardHistory(let count):
            return count > 0 ? String(format: String(localized: "%lld items"), count) : nil
        case .player(.repeatMode):
            switch musicManager.repeatMode {
            case .off: return String(localized: "Off")
            case .all: return String(localized: "All Songs")
            case .one: return String(localized: "This Song")
            }
        default:
            return nil
        }
    }
}

/// A menu row (VISUAL-E §2.11): 28 tall, the label at the panel edge + 16,
/// a value or a shortcut in `textSecondary` 12 from the right, a chevron on
/// rows that open a panel. Highlight: the cursor fill, radius 10.
struct MoreMenuRow: View {
    /// Kept for the callers; E's rows are text only, so it is not drawn.
    var symbol: String? = nil
    let title: String
    let trailing: String?
    var trailingTint: Color = DSE.Palette.textSecondary
    let opensPanel: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .eText(.body)
                    .foregroundStyle(DSE.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .eText(.bodyTabular)
                        .foregroundStyle(trailingTint)
                }
                if opensPanel {
                    Image(systemName: "chevron.right")
                        .font(DSE.Typeface.caption)
                        .foregroundStyle(DSE.Palette.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: DSE.Radius.menuRow, style: .continuous)
                    .fill(isHovering ? DSE.Palette.cursor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
    }
}

/// The status zone at the right of the header: live states only (recording,
/// Keep Awake time, Focus, low battery, paused clipboard history); nothing
/// when nothing is going on. E: no capsule, glyph 15 · 4 · value 12/600,
/// 8 between items (VISUAL-E §2.2).
struct IslandStatusCapsule: View {
    var onKeepAwakeTap: () -> Void = {}
    @ObservedObject private var caffeinate = CaffeinateManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @ObservedObject private var doNotDisturb = DoNotDisturbManager.shared
    @ObservedObject private var recording = ScreenRecordingManager.shared
    @Default(.showBatteryIndicator) private var showBattery
    @Default(.enableClipboardManager) private var enableClipboard
    @Default(.clipboardHistoryPaused) private var clipboardPaused

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
        let showsPaused = enableClipboard && clipboardPaused
        if !items.isEmpty || showsPaused {
            HStack(spacing: 8) {
                if !items.isEmpty {
                    Button(action: onKeepAwakeTap) {
                        HStack(spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                view(for: item)
                            }
                        }
                        .frame(height: DS.hitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressDimStyle())
                    .disabled(!items.contains { if case .keepAwake = $0 { return true } else { return false } })
                }
                if showsPaused {
                    Image(systemName: "pause.circle")
                        .font(DSE.Typeface.glyphOpen)
                        .foregroundStyle(DS.Palette.paused)
                        .help(String(localized: "Clipboard history paused"))
                        .accessibilityLabel(Text("Clipboard history paused"))
                }
            }
            .font(DSE.Typeface.status)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func view(for item: IslandStatus.Item) -> some View {
        switch item {
        case .recording:
            Circle().fill(DS.Palette.danger).frame(width: DSE.Size.dot, height: DSE.Size.dot)
                .accessibilityLabel(Text("Screen recording"))
        case .keepAwake(let remaining):
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(DSE.Typeface.glyphOpen)
                if let remaining {
                    Text(CaffeinateManager.remainingLabel(remaining))
                }
            }
            .foregroundStyle(DSE.Palette.textSecondary)
            .help(String(localized: "Keep Awake"))
        case .focus:
            Image(systemName: "moon.fill")
                .font(DSE.Typeface.glyphOpen)
                .foregroundStyle(Color(rgb: 0x5E5CE6))
                .accessibilityLabel(Text("Focus"))
        case .lowBattery(let percent):
            HStack(spacing: 4) {
                Image(systemName: "battery.25percent")
                    .font(DSE.Typeface.glyphOpen)
                Text("\(percent)%")
            }
            .foregroundStyle(DS.Palette.attention)
        }
    }
}
