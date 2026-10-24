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

/// A view whose keys act on what a click on it selected, where its type
/// cannot be named in `DynamicIslandWindow.clickTarget`: the shelf cell sits
/// inside a generic SwiftUI wrapper. Its mouseDown does not take the first
/// responder, so ⌘A and Delete went to the app in front (24.10).
protocol IslandSelectionClickView: AnyObject {}

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
        // The island is black whatever the system appearance: with macOS in
        // Light mode, views using .primary/.secondary drew dark text on it.
        appearance = NSAppearance(named: .darkAqua)
        isMovable = false
        
        collectionBehavior = Self.pinnedCollectionBehavior
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
        // A click makes the island key only on a view that asks for it: a
        // text field or text view (AppKit's needsPanelToBecomeKey), or what
        // `sendEvent` lets in by `IslandKeyboard.takesKeyboard`: any click
        // in the open island, none on a button of the closed one. A click on
        // the closed island's music wave made it key; it stayed closed, and
        // the app in front lost its keyboard and dictation until the next
        // click elsewhere (24.10). The island's hosting view says no for
        // itself (FirstMouseHostingView), so the decision is `sendEvent`'s.
        becomesKeyOnlyIfNeeded = true

        ScreenCaptureVisibilityManager.shared.register(self, scope: .entireInterface)
    }
    
    /// The unit-test host is a whole second Skerry. Its island used to show
    /// up over the real one, and when a test opened it, it took the keyboard
    /// from whatever the person was typing in. Under tests the window exists
    /// for the code that expects it, but is never shown and never key.
    static var staysHidden: Bool { AppRuntimeEnvironment.isHostingUnitTests }

    override var canBecomeKey: Bool {
        !Self.staysHidden
    }
    
    override var canBecomeMain: Bool {
        !Self.staysHidden
    }

    override func orderFront(_ sender: Any?) {
        guard !Self.staysHidden else { return }
        super.orderFront(sender)
    }

    override func orderFrontRegardless() {
        guard !Self.staysHidden else { return }
        super.orderFrontRegardless()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        guard !Self.staysHidden else { return }
        super.makeKeyAndOrderFront(sender)
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        guard !Self.staysHidden || place == .out else { return }
        super.order(place, relativeTo: otherWin)
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
    /// Opened (or switched to a tab) by a shortcut since it last closed: its
    /// keys stay when typing in it ends.
    private(set) var openedByShortcut = false

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleIslandKey(event) { return }
        if event.type == .leftMouseDown { takeKeyboardIfTheClickAsks(event) }
        super.sendEvent(event)
    }

    /// The island of `viewModel`, for views that ask for the keyboard.
    static func island(showing viewModel: DynamicIslandViewModel) -> DynamicIslandWindow? {
        NSApp.windows.lazy
            .compactMap { $0 as? DynamicIslandWindow }
            .first { $0.islandViewModel === viewModel }
    }

    /// Makes the island the key window, without activating Skerry, when
    /// `request` is one the person asked keys for (24.10).
    func takeKeyboard(_ request: IslandKeyboardRequest) {
        guard IslandKeyboard.takesKeyboard(request, islandOpen: islandViewModel?.notchState == .open) else { return }
        if request == .shortcut { openedByShortcut = true }
        guard canBecomeKey, !isKeyWindow else { return }
        makeKey()
    }

    /// Typing in the island ended (the search field closed): the keyboard
    /// goes back to the app in front unless the island keeps it (24.10).
    func typingEnded() {
        let pointerOnIsland = frame.contains(NSEvent.mouseLocation)
        guard !IslandKeyboard.keepsKeyboardAfterTyping(openedByShortcut: openedByShortcut,
                                                        pointerOnIsland: pointerOnIsland) else { return }
        returnKeyboardIfNeeded()
    }

    /// AppKit is asked only by text fields (needsPanelToBecomeKey); the
    /// open island's buttons, rows and tiles and the terminal are let in here.
    private func takeKeyboardIfTheClickAsks(_ event: NSEvent) {
        guard !isKeyWindow, canBecomeKey else { return }
        // The frame view has no superview: the point is in window coordinates.
        let hit = contentView?.superview?.hitTest(event.locationInWindow)
        takeKeyboard(.click(Self.clickTarget(for: hit)))
    }

    /// What a click landed on, from the view under the pointer up.
    static func clickTarget(for view: NSView?) -> IslandClickTarget {
        var current = view
        while let view = current {
            if typesText(view) || (view as? NSTextField)?.isEditable == true { return .text }
            if view is ScreenshotDragSourceView || view is ClipboardCardInteractionView
                || view is ShelfMarqueeSelectionView.MarqueeView || view is IslandSelectionClickView {
                return .selection
            }
            current = view.superview
        }
        return .control
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
            .sink { [weak self] _ in
                self?.openedByShortcut = false
                self?.returnKeyboardIfNeeded()
            }
    }

    /// Hands the keyboard back now from every island that holds it: a paste
    /// presses ⌘V right after the island closes. Also while Skerry is active
    /// (Settings open): the paste then activates its target, and the island
    /// must not stay key behind it.
    static func returnKeyboardFromIslands() {
        for case let island as DynamicIslandWindow in NSApp.windows {
            island.returnKeyboardIfNeeded(evenWhileActive: true)
        }
    }

    /// The island is out for a moment to give the keyboard back, and comes
    /// back in on the next turn unless something hid it meanwhile.
    private var keyboardReturnPending = false

    override func close() {
        keyboardReturnPending = false
        super.close()
    }

    /// A non-activating panel keeps the keyboard after it closes, so typing
    /// would go nowhere until the user clicks their app. Ordering the island
    /// out and back in hands the keyboard back to the app in front without
    /// activating anything. Back in on the next turn: out and in within one
    /// turn, the window server saw no change and the island kept the
    /// keyboard, so «Вставить в Claude» closed the island and pasted nothing
    /// (23.10). Not while Skerry itself is active (Settings, the terminal),
    /// where AppKit handles focus.
    private func returnKeyboardIfNeeded(evenWhileActive: Bool = false) {
        guard isKeyWindow, isVisible, evenWhileActive || !NSApp.isActive else { return }
        makeFirstResponder(nil)
        orderOut(nil)
        keyboardReturnPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.keyboardReturnPending else { return }
            self.keyboardReturnPending = false
            // The lock screen hides the island with alpha 0 and orderOut; a
            // lock that came in meanwhile keeps it hidden.
            guard !self.isVisible, self.alphaValue > 0 else { return }
            self.orderFrontRegardless()
        }
    }
}
