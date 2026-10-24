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

@testable import Atoll
import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI
import XCTest

/// Global shortcuts: no defaults, suggestions, duplicate check. Nothing here
/// reads or writes the recorded shortcuts.
final class GlobalShortcutTests: XCTestCase {
    private let ctrlOptCmd: NSEvent.ModifierFlags = [.control, .option, .command]

    func testNoShortcutHasADefault() {
        let names = AppShortcuts.all.map(\.name) + [.decreaseBacklight, .increaseBacklight]
        XCTAssertEqual(Set(names.map(\.rawValue)), [
            "toggleNotchOpen", "openScreenshotsTab", "clipboardHistoryPanel", "toggleClipboardPause", "playPause",
            "toggleSneakPeek", "toggleCaffeinate", "startDemoTimer", "screenAssistantPanel", "toggleTerminalTab",
            "colorPickerPanel", "decreaseBacklight", "increaseBacklight",
        ])
        for name in names {
            XCTAssertNil(name.defaultShortcut, "\(name.rawValue) must not have a default shortcut")
        }
    }

    func testSuggestionsAreControlOptionCommandAndDistinct() {
        let suggestions = AppShortcuts.suggestions
        XCTAssertEqual(suggestions[.openScreenshotsTab], .init(.s, modifiers: ctrlOptCmd))
        XCTAssertEqual(suggestions[.clipboardHistoryPanel], .init(.c, modifiers: ctrlOptCmd))
        XCTAssertEqual(suggestions[.playPause], .init(.p, modifiers: ctrlOptCmd))
        XCTAssertEqual(suggestions[.toggleClipboardPause], .init(.v, modifiers: ctrlOptCmd))
        XCTAssertEqual(ShortcutConflicts.duplicates(in: suggestions.map { ($0.key, $0.value) }), [])
    }

    func testTheSameCombinationOnTwoActionsIsAConflict() {
        let s = KeyboardShortcuts.Shortcut(.s, modifiers: ctrlOptCmd)
        let c = KeyboardShortcuts.Shortcut(.c, modifiers: ctrlOptCmd)
        let conflicts = ShortcutConflicts.duplicates(in: [
            (.openScreenshotsTab, s), (.clipboardHistoryPanel, c), (.playPause, s),
        ])
        XCTAssertEqual(conflicts, [[.openScreenshotsTab, .playPause]])
    }

    func testDifferentOrUnsetCombinationsAreNoConflict() {
        let conflicts = ShortcutConflicts.duplicates(in: [
            (.openScreenshotsTab, .init(.s, modifiers: ctrlOptCmd)),
            (.playPause, .init(.s, modifiers: [.control, .command])),
            (.toggleNotchOpen, nil),
            (.toggleSneakPeek, nil),
        ])
        XCTAssertEqual(conflicts, [])
    }

    func testSeveralConflictsAreGroupedInOrder() {
        let p = KeyboardShortcuts.Shortcut(.p, modifiers: ctrlOptCmd)
        let v = KeyboardShortcuts.Shortcut(.v, modifiers: ctrlOptCmd)
        let conflicts = ShortcutConflicts.duplicates(in: [
            (.toggleClipboardPause, v), (.playPause, p), (.toggleSneakPeek, p), (.toggleNotchOpen, v), (.toggleCaffeinate, p),
        ])
        XCTAssertEqual(conflicts, [[.toggleClipboardPause, .toggleNotchOpen], [.playPause, .toggleSneakPeek, .toggleCaffeinate]])
    }
}

final class IslandKeyboardTests: XCTestCase {
    func testIslandKeys() {
        XCTAssertEqual(IslandKeyCommand(keyCode: 53, modifiers: []), .close)
        XCTAssertEqual(IslandKeyCommand(keyCode: 124, modifiers: [.function, .numericPad]), .nextTab)
        XCTAssertEqual(IslandKeyCommand(keyCode: 123, modifiers: [.function, .numericPad]), .previousTab)
        XCTAssertEqual(IslandKeyCommand(keyCode: 48, modifiers: []), .nextTab)
        XCTAssertEqual(IslandKeyCommand(keyCode: 48, modifiers: .shift), .previousTab)
        // With other modifiers the keys stay with whatever handles them (e.g. ⌘← in text).
        XCTAssertNil(IslandKeyCommand(keyCode: 124, modifiers: .command))
        XCTAssertNil(IslandKeyCommand(keyCode: 48, modifiers: .control))
        XCTAssertNil(IslandKeyCommand(keyCode: 53, modifiers: .option))
        XCTAssertNil(IslandKeyCommand(keyCode: 0, modifiers: []))   // A
    }

    func testTabsSwitchInTheUsersOrderSkippingHiddenOnesAndWrapAround() {
        let visible = NotchTabLayout.visibleTabs(
            order: [.nowPlaying, .screenshots, .clipboard, .shelf, .timer],
            hidden: [.shelf],
            isAvailable: { [.nowPlaying, .screenshots, .clipboard, .shelf, .timer].contains($0) }
        )
        XCTAssertEqual(visible, [.nowPlaying, .screenshots, .clipboard, .timer])

        func next(_ view: NotchViews) -> IslandKeyAction? {
            IslandKeyboard.action(for: .nextTab, current: view, visible: visible, hasScreenshotSelection: false)
        }
        func previous(_ view: NotchViews) -> IslandKeyAction? {
            IslandKeyboard.action(for: .previousTab, current: view, visible: visible, hasScreenshotSelection: false)
        }
        XCTAssertEqual(next(.screenshots), .show(.clipboard))
        XCTAssertEqual(next(.clipboard), .show(.timer))          // the hidden Shelf is skipped
        XCTAssertEqual(next(.timer), .show(.home))               // wraps to the first tab
        XCTAssertEqual(previous(.home), .show(.timer))           // and back to the last
        XCTAssertEqual(previous(.timer), .show(.clipboard))
        // From a view that is not a tab (the colour picker view this used went: unreachable).
        XCTAssertEqual(next(.extensionExperience), .show(.home))
        XCTAssertEqual(previous(.extensionExperience), .show(.timer))
    }

    func testOneOrNoVisibleTabDoesNothing() {
        XCTAssertNil(IslandKeyboard.action(for: .nextTab, current: .home, visible: [.nowPlaying], hasScreenshotSelection: false))
        XCTAssertNil(IslandKeyboard.action(for: .previousTab, current: .home, visible: [], hasScreenshotSelection: false))
    }

    func testEscClearsAScreenshotSelectionFirstThenCloses() {
        let visible: [NotchTab] = [.nowPlaying, .screenshots]
        XCTAssertEqual(IslandKeyboard.action(for: .close, current: .screenshots, visible: visible, hasScreenshotSelection: true),
                       .clearScreenshotSelection)
        XCTAssertEqual(IslandKeyboard.action(for: .close, current: .screenshots, visible: visible, hasScreenshotSelection: false),
                       .close)
        XCTAssertEqual(IslandKeyboard.action(for: .close, current: .home, visible: visible, hasScreenshotSelection: true),
                       .close)
    }

    func testTextFieldsKeepTheirKeys() {
        XCTAssertTrue(DynamicIslandWindow.typesText(NSTextView()))
        XCTAssertFalse(DynamicIslandWindow.typesText(NSView()))
        XCTAssertFalse(DynamicIslandWindow.typesText(nil))
    }

    func testScreenshotGridKeys() {
        XCTAssertEqual(ScreenshotGridCommand(keyCode: 49, characters: " ", modifiers: []), .quickLook)
        XCTAssertEqual(ScreenshotGridCommand(keyCode: 53, characters: nil, modifiers: []), .clearSelection)
        XCTAssertEqual(ScreenshotGridCommand(keyCode: 51, characters: nil, modifiers: []), .removeSelected)
        XCTAssertEqual(ScreenshotGridCommand(keyCode: 0, characters: "a", modifiers: .command), .selectAll)
        XCTAssertEqual(ScreenshotGridCommand(keyCode: 8, characters: "c", modifiers: .command), .copy)
        XCTAssertNil(ScreenshotGridCommand(keyCode: 8, characters: "c", modifiers: []))
        XCTAssertNil(ScreenshotGridCommand(keyCode: 49, characters: " ", modifiers: .shift))
    }

    func testHoverOpening() {
        XCTAssertEqual(Defaults.Keys.minimumHoverDuration.defaultValue, 0.15, accuracy: 0.0001)
        XCTAssertTrue(Defaults.Keys.openNotchOnHover.defaultValue)
        XCTAssertEqual(IslandOpening.hoverDelayStep, 0.05, accuracy: 0.0001)
        XCTAssertEqual(IslandOpening.hoverDelayRange, 0...1)
        // "Open only by click": hover never opens the island, a running timer included.
        XCTAssertFalse(IslandOpening.opensOnHover(openNotchOnHover: false))
        XCTAssertTrue(IslandOpening.opensOnHover(openNotchOnHover: true))
    }

    // MARK: Who takes the keyboard (24.10)

    /// Dictation refused to start in the app in front while the island was key after a
    /// click on the closed island's music wave: the closed island never takes
    /// the keyboard on a click; the open one does, as before.
    func testTheClosedIslandNeverTakesTheKeyboardOnAClick() {
        for open in [true, false] {
            XCTAssertTrue(IslandKeyboard.takesKeyboard(.shortcut, islandOpen: open))
            XCTAssertFalse(IslandKeyboard.takesKeyboard(.hover, islandOpen: open))
            XCTAssertTrue(IslandKeyboard.takesKeyboard(.click(.text), islandOpen: open))
            XCTAssertTrue(IslandKeyboard.takesKeyboard(.click(.selection), islandOpen: open),
                          "Delete on a tile must not reach the app in front")
        }
        XCTAssertFalse(IslandKeyboard.takesKeyboard(.click(.control), islandOpen: false), "the closed island's music wave")
        XCTAssertTrue(IslandKeyboard.takesKeyboard(.click(.control), islandOpen: true),
                      "Return, ⌘1…⌘9, Esc and ←/→ after a click on a filter or a button")
    }

    func testWhenTypingEndsTheKeysStayOnlyWithAShortcutOpenedIslandOrUnderThePointer() {
        XCTAssertTrue(IslandKeyboard.keepsKeyboardAfterTyping(openedByShortcut: true, pointerOnIsland: false),
                      "Esc, the arrows and ⌘1…⌘9 keep working")
        XCTAssertTrue(IslandKeyboard.keepsKeyboardAfterTyping(openedByShortcut: false, pointerOnIsland: true),
                      "it closes when the pointer leaves, and closing gives the keyboard back")
        XCTAssertFalse(IslandKeyboard.keepsKeyboardAfterTyping(openedByShortcut: false, pointerOnIsland: false))
    }

    func testWhatAClickLandedOn() {
        let field = NSTextField(frame: .zero)
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: field), .text)
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: NSTextView()), .text)
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: NSTextField(labelWithString: "label")), .control)
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: ScreenshotDragSourceView()), .selection)
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: ShelfMarqueeSelectionView.MarqueeView()), .selection)
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: DraggableClickHandler<EmptyView>.DraggableClickView()), .selection,
                       "a shelf cell: ⌘A and Delete act on the selection")
        let row = ClipboardCardInteractionView()
        let inside = NSView()
        row.addSubview(inside)
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: row), .selection)
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: inside), .selection, "found from the view under the pointer up")
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: NSButton()), .control)
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: nil), .control)
    }

    /// NSHostingView asks a panel to become key on any click, so the island's
    /// own content says no; a SwiftUI text field inside still says yes.
    @MainActor
    func testOnlyTheTextFieldInTheIslandsContentAsksForTheKeyboard() {
        let window = DynamicIslandWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        XCTAssertTrue(window.becomesKeyOnlyIfNeeded)
        struct Content: View {
            @State var query = ""
            var body: some View {
                VStack(spacing: 0) {
                    TextField("Search", text: $query).frame(width: 200, height: 30)
                    Button("Pause") {}.frame(width: 200, height: 30)
                }
            }
        }
        let host = FirstMouseHostingView(rootView: Content())
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(host.needsPanelToBecomeKey)

        // Window coordinates: the field is the top half, the button the bottom.
        let fieldHit = window.contentView?.superview?.hitTest(NSPoint(x: 100, y: 45))
        XCTAssertEqual(fieldHit?.needsPanelToBecomeKey, true, String(describing: fieldHit))
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: fieldHit), .text)
        let buttonHit = window.contentView?.superview?.hitTest(NSPoint(x: 100, y: 15))
        XCTAssertEqual(buttonHit?.needsPanelToBecomeKey, false, String(describing: buttonHit))
        XCTAssertEqual(DynamicIslandWindow.clickTarget(for: buttonHit), .control)
    }

    /// Under tests the island is never key, but it still notes the shortcut.
    @MainActor
    func testOnlyTheShortcutMarksTheIslandAsOpenedByIt() {
        let window = DynamicIslandWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.takeKeyboard(.hover)
        window.takeKeyboard(.click(.selection))
        XCTAssertFalse(window.openedByShortcut)
        window.takeKeyboard(.shortcut)
        XCTAssertTrue(window.openedByShortcut)
        XCTAssertFalse(window.isKeyWindow)
    }

    func testHoverDelayLabel() {
        let english = IslandOpening.hoverDelayLabel(seconds: 0.15, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(english.contains("150") && english.contains("ms"), english)
        let russian = IslandOpening.hoverDelayLabel(seconds: 0.15, locale: Locale(identifier: "ru_RU"))
        XCTAssertTrue(russian.contains("150") && russian.contains("мс"), russian)
        XCTAssertTrue(IslandOpening.hoverDelayLabel(seconds: 0.05, locale: Locale(identifier: "en_US")).contains("50"))
    }
}
