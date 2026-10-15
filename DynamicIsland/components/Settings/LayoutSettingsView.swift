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
import UniformTypeIdentifiers

/// Settings → Layout: which island tabs are shown, their order and which one
/// the island opens on; what the closed island shows and in which priority.
struct LayoutSettingsView: View {
    /// Maps a row title to its settings-search highlight id.
    let highlightID: (String) -> String

    @Default(.notchTabOrder) private var order
    @Default(.notchHiddenTabs) private var hidden
    @Default(.defaultNotchTab) private var defaultTab
    @Default(.closedMusicStyle) private var musicStyle
    @Default(.closedIndicatorPriority) private var priority
    @Default(.openNotchOnHover) private var openOnHover
    @Default(.minimumHoverDuration) private var hoverDelay
    @Default(.enableGestures) private var enableGestures
    @Default(.hideNotchOption) private var hideNotchOption
    @State private var dropTarget: NotchTab?
    @State private var indicatorDropTarget: ClosedIndicator?

    /// Screenshots are part of the Clipboard tab and have no row of their own.
    private var orderedTabs: [NotchTab] { NotchTabLayout.normalizedOrder(order).filter { !$0.isMergedIntoClipboard } }
    private var orderedIndicators: [ClosedIndicator] { ClosedIndicatorResolver.normalizedOrder(priority) }

    var body: some View {
        Form {
            Section {
                ForEach(orderedTabs) { tab in
                    tabRow(tab)
                }
            } header: {
                Text("Tabs")
            } footer: {
                Text("Drag a row to change the order. A tab whose feature is off stays hidden until you turn the feature on.")
            }
            .settingsHighlight(id: highlightID("Tabs"))

            Section {
                Toggle("Open only by click", isOn: Binding(
                    get: { !openOnHover },
                    set: { clickOnly in
                        openOnHover = !clickOnly
                        // As in upstream: without hover opening, gestures stay on (swipe down opens).
                        if clickOnly { enableGestures = true }
                    }
                ))
                .settingsHighlight(id: highlightID("Open only by click"))

                if openOnHover {
                    Slider(value: $hoverDelay, in: IslandOpening.hoverDelayRange, step: IslandOpening.hoverDelayStep) {
                        HStack {
                            Text("Hover delay")
                            Spacer()
                            Text(IslandOpening.hoverDelayLabel(seconds: hoverDelay))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: highlightID("Hover delay"))
                }

                Picker("Open the island on", selection: $defaultTab) {
                    Text("Last opened tab").tag(NotchTab?.none)
                    Divider()
                    ForEach(orderedTabs) { tab in
                        Text(tab.title).tag(NotchTab?.some(tab))
                    }
                }
                .settingsHighlight(id: highlightID("Open the island on"))

                // Was under Shelf, where it overrode the choice above unseen.
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open on the Shelf while it holds files")
                }
                .settingsHighlight(id: highlightID("Open on the Shelf while it holds files"))

                Defaults.Toggle(key: .openScreenshotsOnNewScreenshot) {
                    Text("Open Screenshots when a new screenshot arrives")
                }
                .settingsHighlight(id: highlightID("Open Screenshots when a new screenshot arrives"))

                Defaults.Toggle(key: .openShelfOnFileDrag) {
                    Text("Open the Shelf when a file is dragged onto the island")
                }
                .settingsHighlight(id: highlightID("Open the Shelf when a file is dragged onto the island"))
            } header: {
                Text("Opening")
            } footer: {
                Text("A click in the island or a shortcut that opens it gives it the keyboard: Esc closes it, ← → and Tab switch tabs. Opening on hover leaves the keyboard with the app you are working in.")
            }

            Section {
                Picker("Music on the closed island", selection: $musicStyle) {
                    ForEach(ClosedMusicStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .settingsHighlight(id: highlightID("Music on the closed island"))

                // The one place for this (Media had a second picker for it).
                Picker("In full-screen apps", selection: Binding(
                    get: { hideNotchOption },
                    set: { option in
                        hideNotchOption = option
                        Defaults[.enableFullscreenMediaDetection] = option != .never
                    }
                )) {
                    Text("Hide the island").tag(HideNotchOption.always)
                    Text("Hide while the music app is full screen").tag(HideNotchOption.nowPlayingOnly)
                    Text("Keep showing it").tag(HideNotchOption.never)
                }
                .settingsHighlight(id: highlightID("Hide the island in full-screen apps"))

                Defaults.Toggle(key: .hideContentWhilePresenting) {
                    Text("Hide clipboard and screenshots while the screen is shared")
                }
                .settingsHighlight(id: highlightID("Hide clipboard and screenshots while the screen is shared"))
            } header: {
                Text("Closed island")
            } footer: {
                Text("Without full-screen hiding, the island still hides when the app playing music is in full screen. While the screen is shared or recorded, the Clipboard and Screenshots tabs show only their titles and the island shows no notifications other than volume, brightness and Caps Lock.")
            }

            Section {
                ForEach(Array(orderedIndicators.enumerated()), id: \.element) { index, indicator in
                    indicatorRow(indicator, position: index + 1)
                }
                Button("Restore Default Order") {
                    withAnimation(.smooth(duration: 0.2)) { priority = ClosedIndicator.defaultOrder }
                }
                .disabled(orderedIndicators == ClosedIndicator.defaultOrder)
            } header: {
                Text("Indicator priority")
            } footer: {
                Text("When several indicators are active, the closed island shows the highest one. Volume, brightness, battery and Caps Lock always come first. While music plays, the clipboard pause, timer, reminder, screen recording, Focus, extensions and shelf appear as a badge on the artwork instead of replacing it; the highest of them gets the badge.")
            }
            .settingsHighlight(id: highlightID("Indicator priority"))
        }
        .formStyle(.grouped)
        .navigationTitle("Layout")
    }

    private func tabRow(_ tab: NotchTab) -> some View {
        let available = tab.isFeatureAvailable
        let isOn = Binding<Bool>(
            get: { !hidden.contains(tab) },
            set: { show in
                if show { hidden.removeAll { $0 == tab } } else if !hidden.contains(tab) { hidden.append(tab) }
            }
        )
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("Drag to reorder")
            Image(systemName: tab.icon)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                if !available {
                    Text(tab.featureHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .disabled(!available)
                .accessibilityLabel(Text(tab.title))
        }
        .padding(.vertical, 2)
        .opacity(available ? 1 : 0.6)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if dropTarget == tab {
                Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: -4)
            }
        }
        .onDrag {
            NSItemProvider(object: NSString(string: "notchtab:\(tab.rawValue)"))
        }
        .onDrop(of: [UTType.plainText], isTargeted: Binding(
            get: { dropTarget == tab },
            set: { targeted in dropTarget = targeted ? tab : (dropTarget == tab ? nil : dropTarget) }
        )) { providers in
            handleDrop(providers, onto: tab)
        }
    }

    private func indicatorRow(_ indicator: ClosedIndicator, position: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("Drag to reorder")
            Text("\(position)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Image(systemName: indicator.icon)
                .frame(width: 20)
            Text(indicator.title)
            Spacer()
            if indicator.pairsWithMusic {
                Text("Badge with music")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if indicatorDropTarget == indicator {
                Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: -4)
            }
        }
        .onDrag {
            NSItemProvider(object: NSString(string: "closedindicator:\(indicator.rawValue)"))
        }
        .onDrop(of: [UTType.plainText], isTargeted: Binding(
            get: { indicatorDropTarget == indicator },
            set: { targeted in
                indicatorDropTarget = targeted ? indicator : (indicatorDropTarget == indicator ? nil : indicatorDropTarget)
            }
        )) { providers in
            handleIndicatorDrop(providers, onto: indicator)
        }
    }

    private func handleIndicatorDrop(_ providers: [NSItemProvider], onto target: ClosedIndicator) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, text.hasPrefix("closedindicator:"),
                  let dragged = ClosedIndicator(rawValue: String(text.dropFirst("closedindicator:".count))) else { return }
            DispatchQueue.main.async {
                withAnimation(.smooth(duration: 0.2)) {
                    priority = ClosedIndicatorResolver.move(dragged, onto: target, in: priority)
                }
                indicatorDropTarget = nil
            }
        }
        return true
    }

    private func handleDrop(_ providers: [NSItemProvider], onto target: NotchTab) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, text.hasPrefix("notchtab:"),
                  let dragged = NotchTab(rawValue: String(text.dropFirst("notchtab:".count))) else { return }
            DispatchQueue.main.async {
                withAnimation(.smooth(duration: 0.2)) {
                    order = NotchTabLayout.move(dragged, onto: target, in: order)
                }
                dropTarget = nil
            }
        }
        return true
    }
}
