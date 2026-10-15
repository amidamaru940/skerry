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

import Cocoa
import Combine
import SwiftTerm

class DynamicIslandWindow: NSPanel {
    static let pinnedCollectionBehavior: NSWindow.CollectionBehavior = [
        .fullScreenAuxiliary,
        .canJoinAllSpaces,
        .ignoresCycle,
        .stationary,
    ]

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        
        collectionBehavior = Self.pinnedCollectionBehavior
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false

        ScreenCaptureVisibilityManager.shared.register(self, scope: .entireInterface)
    }
    
    override var canBecomeKey: Bool {
        true
    }
    
    override var canBecomeMain: Bool {
        true
    }

    // MARK: Keyboard (Skerry)

    /// The island shown in this window: its keys act on it, and it hands the
    /// keyboard back to the app in front when it closes.
    weak var islandViewModel: DynamicIslandViewModel? {
        didSet { observeIslandState() }
    }
    /// Called when an island key was handled (keeps a shortcut-opened island open).
    var onIslandKeyCommand: (() -> Void)?
    private var islandStateObserver: AnyCancellable?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleIslandKey(event) { return }
        super.sendEvent(event)
    }

    /// Esc, ←/→ and Tab/⇧Tab in the open island, unless a text field, the
    /// notes editor or the terminal has the keyboard.
    private func handleIslandKey(_ event: NSEvent) -> Bool {
        guard let viewModel = islandViewModel, viewModel.notchState == .open,
              !Self.typesText(firstResponder),
              let command = IslandKeyCommand(keyCode: event.keyCode, modifiers: event.modifierFlags) else { return false }
        let coordinator = DynamicIslandViewCoordinator.shared
        let screenshots = ScreenshotShelfManager.shared
        guard let action = IslandKeyboard.action(
            for: command,
            current: coordinator.currentView,
            visible: NotchTabLayout.visibleTabs,
            hasScreenshotSelection: !screenshots.selection.isEmpty
        ) else { return false }

        onIslandKeyCommand?()
        switch action {
        case .close:
            viewModel.close()
        case .clearScreenshotSelection:
            screenshots.clearSelection()
        case .show(let view):
            coordinator.currentView = view
        }
        return true
    }

    /// Text fields and editors (their field editor or text view is an
    /// NSText) and the terminal keep every key for themselves.
    static func typesText(_ responder: NSResponder?) -> Bool {
        responder is NSText || responder is TerminalView
    }

    private func observeIslandState() {
        islandStateObserver = islandViewModel?.$notchState
            .removeDuplicates()
            .filter { $0 == .closed }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.returnKeyboardIfNeeded() }
    }

    /// A non-activating panel keeps the keyboard after it closes, so typing
    /// would go nowhere until the user clicks their app. Ordering the island
    /// out and straight back in hands the keyboard back to the app in front
    /// without activating anything. Not while Skerry itself is active
    /// (Settings, the terminal), where AppKit handles focus.
    private func returnKeyboardIfNeeded() {
        guard isKeyWindow, isVisible, !NSApp.isActive else { return }
        makeFirstResponder(nil)
        orderOut(nil)
        orderFrontRegardless()
    }
}
