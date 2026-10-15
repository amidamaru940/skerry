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
import Defaults
import SwiftUI
import UniformTypeIdentifiers

/// Names and icons of installed apps, by bundle identifier.
enum InstalledApps {
    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func isInstalled(_ bundleID: String) -> Bool { url(for: bundleID) != nil }

    static func displayName(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage {
        guard let url = url(for: bundleID) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Lets the user pick apps in /Applications; returns their bundle identifiers.
    @MainActor
    static func pick(prompt: String) -> [String] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = prompt
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }
}

/// Settings → Media, for the Auto source: which player wins and which apps
/// are never shown.
struct AutoMediaSettingsSection: View {
    let highlightID: (String) -> String

    @Default(.autoMediaSourceOrder) private var order
    @Default(.autoMediaIgnoredApps) private var ignoredApps
    @State private var dropTarget: AutoMediaSource?

    private var orderedSources: [AutoMediaSource] { AutoSourceResolver.normalizedOrder(order) }

    private var installedBrowsers: [String] {
        AutoMediaSource.browserBundleIDs.filter(InstalledApps.isInstalled)
    }

    var body: some View {
        Section {
            ForEach(Array(orderedSources.enumerated()), id: \.element) { index, source in
                sourceRow(source, position: index + 1)
            }
        } header: {
            Text("Auto: priority")
        } footer: {
            Text("When several players play at once, the highest one is shown. Drag a row to change the order.")
        }
        .settingsHighlight(id: highlightID("Auto: priority"))

        Section {
            ForEach(ignoredApps, id: \.self) { bundleID in
                HStack {
                    Image(nsImage: InstalledApps.icon(for: bundleID))
                        .resizable()
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(InstalledApps.displayName(for: bundleID))
                        Text(bundleID)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        ignoredApps.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            }

            HStack {
                Button("Add App…") {
                    for bundleID in InstalledApps.pick(prompt: String(localized: "Ignore")) where !ignoredApps.contains(bundleID) {
                        ignoredApps.append(bundleID)
                    }
                }
                Spacer()
                Button("Ignore Browsers") {
                    for bundleID in installedBrowsers where !ignoredApps.contains(bundleID) {
                        ignoredApps.append(bundleID)
                    }
                }
                .disabled(installedBrowsers.allSatisfy(ignoredApps.contains))
            }
        } header: {
            Text("Auto: ignored apps")
        } footer: {
            Text("Players in these apps are never shown in the island, for example videos in a browser. When one of them plays, the island shows the next player that is not ignored.")
        }
        .settingsHighlight(id: highlightID("Auto: ignored apps"))
    }

    private func sourceRow(_ source: AutoMediaSource, position: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("Drag to reorder")
            Text("\(position)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            if let bundleID = source.bundleIdentifier {
                Image(nsImage: InstalledApps.icon(for: bundleID))
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "globe")
                    .frame(width: 18)
            }
            Text(source.title)
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if dropTarget == source {
                Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: -4)
            }
        }
        .onDrag {
            NSItemProvider(object: NSString(string: "automediasource:\(source.rawValue)"))
        }
        .onDrop(of: [UTType.plainText], isTargeted: Binding(
            get: { dropTarget == source },
            set: { targeted in dropTarget = targeted ? source : (dropTarget == source ? nil : dropTarget) }
        )) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String, text.hasPrefix("automediasource:"),
                      let dragged = AutoMediaSource(rawValue: String(text.dropFirst("automediasource:".count))) else { return }
                DispatchQueue.main.async {
                    withAnimation(.smooth(duration: 0.2)) {
                        order = AutoSourceResolver.move(dragged, onto: source, in: order)
                    }
                    dropTarget = nil
                }
            }
            return true
        }
    }
}
