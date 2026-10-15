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

/// The top row of the open island: the tabs on the left, the camera notch,
/// and on the right a capsule for live states plus one "…" button whose
/// popover holds what used to be six separate buttons (docs/PLAN-DESIGN.md
/// §3.2).
struct DynamicIslandHeader: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @State private var showMore = false
    @State private var morePanel: IslandMoreMenu.Panel = .menu
    @Default(.clipboardDisplayMode) var clipboardDisplayMode
    @Default(.enableCaffeinate) var enableCaffeinate
    @Default(.enableColorPickerFeature) var enableColorPicker
    @Default(.enablePerAppVolume) var enablePerAppVolume

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                // Always the tabs: the retired minimalistic mode hid them, and
                // with them every way back.
                let shouldShowTabs = coordinator.alwaysShowTabs || vm.notchState == .open || !shelfState.items.isEmpty
                if shouldShowTabs {
                    TabSelectionView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
            .padding(.horizontal, DS.Space.s)

            if vm.notchState == .open {
                let spacerWidth = min(vm.closedNotchSize.width, 300)
                Rectangle()
                    .fill(NSScreen.screens
                        .first(where: { $0.localizedName == coordinator.selectedScreen })?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: spacerWidth)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: DS.Space.s) {
                if vm.notchState == .open {
                    IslandStatusCapsule { toggleMore(.keepAwake) }
                    DSIconButton(symbol: "ellipsis", label: String(localized: "More"), isSelected: showMore) {
                        toggleMore(.menu)
                    }
                    .popover(isPresented: $showMore, arrowEdge: .bottom) {
                        IslandMoreMenuView(panel: $morePanel, isPresented: $showMore)
                            .environmentObject(vm)
                            .environmentObject(webcamManager)
                    }
                }

            }
            .padding(.trailing, DS.Space.s)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
        }
        .environmentObject(vm)
        .onChange(of: showMore) { _, active in
            vm.isMoreMenuActive = active
            if !active {
                morePanel = .menu
                // The pointer may have left the island while the popover was open.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    vm.shouldRecheckHover.toggle()
                }
            }
        }
        .onChange(of: vm.notchState) { _, state in
            if state == .closed { showMore = false }
        }
        .onChange(of: coordinator.shouldToggleClipboardPopover) { _ in
            guard Defaults[.enableClipboardManager] else { return }
            switch clipboardDisplayMode {
            case .panel:
                ClipboardPanelManager.shared.toggleClipboardPanel()
            case .popover:
                toggleMore(.clipboard)
            case .separateTab:
                coordinator.currentView = coordinator.currentView == .notes ? .home : .notes
            case .notchTab:
                // Don't let the auto-close armed by the open shortcut fire after switching tabs.
                AppDelegate.shared?.cancelPendingNotchAutoClose()
                coordinator.currentView = coordinator.currentView == .clipboard ? .home : .clipboard
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleClipboardPopover"))) { _ in
            // The clipboard shortcut in popover mode.
            if Defaults[.enableClipboardManager] && clipboardDisplayMode == .popover {
                toggleMore(.clipboard)
            }
        }
        // A panel whose feature was just turned off goes back to the menu.
        .onChange(of: enableCaffeinate) { _, on in if !on && morePanel == .keepAwake { morePanel = .menu } }
        .onChange(of: enableColorPicker) { _, on in if !on && morePanel == .colorPicker { morePanel = .menu } }
        .onChange(of: enablePerAppVolume) { _, on in if !on && morePanel == .appVolume { morePanel = .menu } }
    }

    /// Opens the "…" popover on `panel`, or closes it when it already shows it.
    private func toggleMore(_ panel: IslandMoreMenu.Panel) {
        if showMore && morePanel == panel {
            showMore = false
        } else {
            morePanel = panel
            showMore = true
        }
    }
}

#Preview {
    DynamicIslandHeader()
        .environmentObject(DynamicIslandViewModel())
        .environmentObject(WebcamManager.shared)
}
