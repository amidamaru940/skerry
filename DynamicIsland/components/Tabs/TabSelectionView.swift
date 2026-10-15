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

import AtollExtensionKit
import SwiftUI
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let experienceID: String?
    let accentColor: Color?
    let badge: TabBadge?

    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil, badge: TabBadge? = nil) {
        self.id = experienceID.map { "extension-\($0)" } ?? "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
        self.experienceID = experienceID
        self.accentColor = accentColor
        self.badge = badge
    }
}

/// Small marker on a tab: something new since the tab was last looked at,
/// or clipboard history paused.
enum TabBadge: Equatable {
    case new
    case paused
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    // Layout and the features behind the tabs, so the bar refreshes when they change.
    @Default(.islandLayout) private var islandLayout
    @Default(.notchTabOrder) private var notchTabOrder
    @Default(.notchHiddenTabs) private var notchHiddenTabs
    @Default(.enableScreenshotShelf) private var enableScreenshotShelf
    @Default(.enableClipboardManager) private var enableClipboardManager
    @Default(.clipboardDisplayMode) private var clipboardDisplayMode
    @Default(.clipboardHistoryPaused) private var clipboardHistoryPaused
    @Default(.dynamicShelf) private var dynamicShelf
    @ObservedObject private var screenshots = ScreenshotShelfManager.shared
    @ObservedObject private var clipboard = ClipboardManager.shared
    @ObservedObject private var shelf = ShelfStateViewModel.shared
    @ObservedObject private var newItems = TabNewItemsTracker.shared
    
    private var tabs: [TabModel] {
        // Standard tabs in the order and visibility chosen in Layout settings.
        var tabsArray: [TabModel] = NotchTabLayout.visibleTabs.map { tab in
            if tab == .notes && !Defaults[.enableNotes] {
                // Notes off but clipboard in "separate tab" mode: upstream labels it Clipboard.
                return TabModel(label: NotchTab.clipboard.title, icon: NotchTab.clipboard.icon, view: .notes)
            }
            return TabModel(label: tab.title, icon: tab.icon, view: tab.view, badge: badge(for: tab))
        }

        if extensionTabsEnabled {
            for payload in extensionTabPayloads {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                tabsArray.append(
                    TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                )
            }
        }
        return tabsArray
    }
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(tabs) { tab in
                TabButton(
                    label: tab.label,
                    icon: tab.icon,
                    selected: isSelected(tab),
                    badge: tab.badge,
                    accent: tab.accentColor
                ) {
                    withAnimation(DS.spring) {
                        if tab.view == .extensionExperience {
                            coordinator.selectedExtensionExperienceID = tab.experienceID
                        }
                        coordinator.currentView = tab.view
                    }
                }
            }
        }
        .onAppear {
            ensureValidSelection(with: tabs)
            markCurrentTabSeen()
        }
        .onChange(of: tabs.map(\.id)) {
            ensureValidSelection(with: tabs)
        }
        .onChange(of: coordinator.currentView) { markCurrentTabSeen() }
        .onChange(of: itemIDs(for: .screenshots)) { markCurrentTabSeen() }
        .onChange(of: itemIDs(for: .clipboard)) { markCurrentTabSeen() }
        .onChange(of: itemIDs(for: .shelf)) { markCurrentTabSeen() }
    }

    /// The items of a tab, by identity, for the "new" dot.
    private func itemIDs(for tab: NotchTab) -> Set<String> {
        switch tab {
        case .screenshots:
            return Set(screenshots.store.batches.flatMap(\.items).map(\.path))
        case .clipboard:
            // The screenshots are part of this tab now.
            return Set(clipboard.clipboardHistory.map(\.id.uuidString))
                .union(screenshots.store.batches.flatMap(\.items).map(\.path))
        case .shelf:
            return Set(shelf.items.map(\.id.uuidString))
        default:
            return []
        }
    }

    /// The tab on screen has been seen, together with whatever arrives
    /// while it is open.
    private func markCurrentTabSeen() {
        guard let tab = NotchTab(view: coordinator.currentView) else { return }
        newItems.markSeen(tab, current: itemIDs(for: tab))
    }

    private func badge(for tab: NotchTab) -> TabBadge? {
        _ = newItems.revision
        if tab == .clipboard && clipboardHistoryPaused { return .paused }
        switch tab {
        case .screenshots, .clipboard, .shelf:
            return newItems.hasNew(tab, current: itemIDs(for: tab)) ? .new : nil
        default:
            return nil
        }
    }

    private var extensionTabsEnabled: Bool {
        enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        if tab.view == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        if first.view == .extensionExperience {
            coordinator.selectedExtensionExperienceID = first.experienceID
        } else {
            coordinator.selectedExtensionExperienceID = nil
        }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
