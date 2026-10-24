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

/// Settings → Screenshots: the batch options and a setup helper for where
/// macOS saves screenshots.
struct ScreenshotsSettingsView: View {
    /// Maps a row title to its settings-search highlight id.
    let highlightID: (String) -> String

    @ObservedObject private var manager = ScreenshotShelfManager.shared
    @Default(.enableScreenshotShelf) private var enabled
    @Default(.screenshotBatchGapMinutes) private var gapMinutes
    @Default(.collectClipboardScreenshots) private var collectClipboard

    @State private var confirmUseFolder = false
    @State private var confirmHideThumbnail = false
    @State private var thumbnailShown = ScreenshotSystemSettings.isFloatingThumbnailShown
    @State private var canUndoThumbnail = ScreenshotSystemSettings.canUndoHideThumbnail
    @State private var folderChangeFailed = false

    private var folder: URL { manager.folder }
    private var recommended: URL { ScreenshotLocation.recommendedFolder() }

    var body: some View {
        Form {
            Section {
                // One feature: the switch takes the clipboard part along
                // (ScreenshotFeature); the clipboard part can then be turned
                // off on its own below.
                Toggle(isOn: Binding(get: { enabled }, set: { ScreenshotFeature.setEnabled($0) })) {
                    Text("Collect new screenshots")
                }
                .settingsHighlight(id: highlightID("Collect new screenshots"))

                Picker("Start a new batch after", selection: $gapMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!enabled)
                .settingsHighlight(id: highlightID("Start a new batch after"))

                Defaults.Toggle(key: .screenshotMoveOriginalsToTrash) {
                    Text("Move originals to Trash when removed")
                }
                .disabled(!enabled)
                .settingsHighlight(id: highlightID("Move originals to Trash when removed"))

                Defaults.Toggle(key: .screenshotRemoveAfterDrag) {
                    Text("Remove from batch after a successful drag")
                }
                .disabled(!enabled)
                .settingsHighlight(id: highlightID("Remove from batch after a successful drag"))

                Defaults.Toggle(key: .collectScreenRecordings) {
                    Text("Also collect screen recordings (.mov)")
                }
                .disabled(!enabled)
                .settingsHighlight(id: highlightID("Also collect screen recordings (.mov)"))
            } header: {
                Text("Screenshot Batches")
            } footer: {
                Text("Screenshots taken in a row gather in one batch on the shelf. Removing a screenshot from a batch keeps the file unless the Trash option is on.")
            }

            Section {
                Defaults.Toggle(key: .collectClipboardScreenshots) {
                    Text("Also collect clipboard screenshots")
                }
                .disabled(!enabled)
                .settingsHighlight(id: highlightID("Also collect clipboard screenshots"))

                if collectClipboard {
                    Label("A screenshot taken to the clipboard (⌃⇧⌘3, ⌃⇧⌘4) joins the screenshot batches instead of the clipboard history. It is not kept on the Mac: it waits in a temporary folder only so it can be pasted or dragged, and is deleted when you remove it, clear its batch or quit Skerry, and after a day. Paused clipboard history, concealed copies and ignored apps are skipped.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Clipboard Screenshots")
            } footer: {
                Text("Screenshots taken to the clipboard create no file. macOS does not mark them, so a picture counts as a screenshot when it reaches the clipboard while the system screenshot tool is running. With this off, they are ordinary pictures in the clipboard history.")
            }

            Section {
                LabeledContent("Screenshots are saved to") {
                    Text(folder.path.replacingOccurrences(of: ScreenshotLocation.home.path, with: "~"))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                if ScreenshotLocation.isDesktopOrDocuments(folder) {
                    Label("These folders sync with iCloud (when Desktop & Documents sync is on), and Skerry needs macOS permission to read them. ~/Screenshots needs neither.", systemImage: "icloud.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Use ~/Screenshots") { confirmUseFolder = true }
                        .settingsHighlight(id: highlightID("Use ~/Screenshots"))
                }

                if !manager.canReadFolder {
                    Label("Skerry cannot read this folder. Allow it in System Settings → Privacy & Security → Files and Folders → Skerry, or switch to ~/Screenshots.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    HStack {
                        Button("Open Privacy Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button("Check Again") { manager.refreshFolder() }
                    }
                }

                if folderChangeFailed {
                    Text("The screenshot folder could not be changed.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Where Screenshots Are Saved")
            }

            Section {
                LabeledContent("Floating thumbnail") {
                    Text(thumbnailShown ? "Shown" : "Hidden")
                        .foregroundStyle(.secondary)
                }
                if thumbnailShown {
                    Button("Hide macOS floating thumbnail") { confirmHideThumbnail = true }
                        .settingsHighlight(id: highlightID("Hide macOS floating thumbnail"))
                }
                if canUndoThumbnail {
                    Button("Undo: show the floating thumbnail again") {
                        ScreenshotSystemSettings.undoHideFloatingThumbnail()
                        refreshThumbnailState()
                    }
                }
            } header: {
                Text("macOS Floating Thumbnail")
            } footer: {
                Text("While the thumbnail is on screen, macOS waits about 5 seconds before saving the file, so the screenshot reaches the batch late.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Screenshots")
        .onAppear {
            manager.refreshFolder()
            refreshThumbnailState()
        }
        // Collecting turned on here is the person asking for screenshots:
        // the folder is first looked at then on a fresh install (§5.8). The
        // clipboard part alone needs no folder, so it asks for none.
        .onChange(of: enabled) { _, on in if on { manager.startOnFirstUse() } }
        .confirmationDialog("Save screenshots to ~/Screenshots?", isPresented: $confirmUseFolder) {
            Button("Use ~/Screenshots") {
                folderChangeFailed = !manager.useRecommendedFolder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This creates \(recommended.path), tells macOS to save screenshots there and restarts the menu bar for a moment. Existing screenshots are not moved.")
        }
        .confirmationDialog("Hide the floating thumbnail after screenshots?", isPresented: $confirmHideThumbnail) {
            Button("Hide Thumbnail") {
                ScreenshotSystemSettings.hideFloatingThumbnail()
                refreshThumbnailState()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This tells macOS not to show the floating thumbnail and restarts the menu bar for a moment. You can undo it here.")
        }
    }

    private func refreshThumbnailState() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            thumbnailShown = ScreenshotSystemSettings.isFloatingThumbnailShown
            canUndoThumbnail = ScreenshotSystemSettings.canUndoHideThumbnail
        }
    }
}
