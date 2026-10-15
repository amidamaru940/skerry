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

/// "Paste into Claude · 3": copies the batch (or the screenshots selected in
/// it) and pastes it into the app the user was working in.
struct BatchPasteButton: View {
    let batch: ScreenshotBatch
    var kind: DSButtonStyle.Kind = .primary
    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @ObservedObject private var target = PasteTarget.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel

    var body: some View {
        let count = manager.pasteURLs(for: batch).count
        Button {
            let result = manager.paste(batch: batch) { vm.close() }
            if result == .copiedOnly {
                BufferTabState.shared.show(toast: BufferTabState.copiedHint)
            }
        } label: {
            Text(BufferLayout.pasteTitle(count: count, target: target.name, canPaste: ClipboardPaster.isAccessibilityTrusted()))
                .lineLimit(1)
        }
        .buttonStyle(DSButtonStyle(kind: kind, height: 26))
        .fixedSize()
        .help(String(localized: "Copy these screenshots and paste them into the app you were working in"))
    }
}

/// The "…" of a batch: Quick Look, AirDrop, Finder, Markup, remove the
/// selected ones, clear the batch. Each acts on the selected screenshots of
/// the batch, or on all of them.
struct BatchActionsMenu: View {
    let batch: ScreenshotBatch
    @ObservedObject var quickLook: QuickLookService
    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var isPresented = false
    @State private var token = UUID()

    var body: some View {
        DSIconButton(symbol: "ellipsis", label: String(localized: "More"), isSelected: isPresented) {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            let urls = manager.pasteURLs(for: batch)
            let selected = manager.selectedCount(in: batch)
            VStack(spacing: 2) {
                row("eye", "Quick Look") { quickLook.show(urls: urls) }
                row("dot.radiowaves.up.forward", "AirDrop") { manager.airDrop(urls) }
                row("folder", "Show in Finder") { manager.reveal(urls) }
                if !urls.isEmpty {
                    // Several open one after another (MarkupQueue).
                    row("pencil.tip.crop.circle", urls.count > 1 ? "Markup · \(urls.count)" : "Markup") { manager.markup(urls) }
                }
                Divider().padding(.vertical, 4).padding(.horizontal, 8)
                if selected > 0 {
                    row("minus.circle", "Remove from batch") { manager.removeSelected(in: batch) }
                }
                row("xmark.circle", "Clear batch") { manager.requestClear(batch) }
            }
            .padding(6)
            .frame(width: 230)
        }
        .onChange(of: isPresented) { _, presented in
            vm.setAutoCloseSuppression(presented, token: token)
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: token) }
    }

    private func row(_ symbol: String, _ title: String.LocalizationValue, action: @escaping () -> Void) -> some View {
        MoreMenuRow(symbol: symbol, title: String(localized: title), trailing: nil, trailingTint: DS.Palette.textTertiary, opensPanel: false) {
            isPresented = false
            action()
        }
    }
}

/// "Select All" for a batch, "Deselect" once all of it is chosen.
struct BatchSelectAllButton: View {
    let batch: ScreenshotBatch
    @ObservedObject private var manager = ScreenshotShelfManager.shared

    var body: some View {
        Button(manager.isFullySelected(batch) ? String(localized: "Deselect") : String(localized: "Select All")) {
            withAnimation(DS.hover) { manager.toggleSelectAll(in: batch) }
        }
        .buttonStyle(DSButtonStyle(kind: .quiet, height: 26))
        .fixedSize()
    }
}
