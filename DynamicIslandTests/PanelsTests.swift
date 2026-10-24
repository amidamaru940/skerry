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
import SwiftUI
import XCTest

/// Step D5: Keep Awake, the one timer, popovers of one width.
@MainActor
final class PanelsTests: XCTestCase {
    // MARK: Keep Awake

    func testKeepAwakeSaysWhatIsGoingOn() {
        let off = KeepAwakeStatus.title(isActive: false, remaining: nil)
        let forever = KeepAwakeStatus.title(isActive: true, remaining: nil)
        let timed = KeepAwakeStatus.title(isActive: true, remaining: 895)
        XCTAssertNotEqual(off, forever)
        XCTAssertTrue(timed.contains("14:55"), timed)
        XCTAssertFalse(forever.contains("14:55"))
    }

    func testChoosingTheRunningDurationDoesNotRestartIt() {
        XCTAssertFalse(KeepAwakeStatus.shouldStart(.oneHour, isActive: true, active: .oneHour))
        XCTAssertTrue(KeepAwakeStatus.shouldStart(.twoHours, isActive: true, active: .oneHour))
        XCTAssertTrue(KeepAwakeStatus.shouldStart(.oneHour, isActive: false, active: nil))
    }

    func testDurationsFitOneRowShortestFirst() {
        let order = CaffeinateDuration.panelOrder
        XCTAssertEqual(order.count, 5, "one row that fits 280 pt")
        XCTAssertEqual(Set(order).union([.fourHours]), Set(CaffeinateDuration.allCases), "four hours stays in Settings")
        XCTAssertEqual(order.first, .fifteenMinutes)
        XCTAssertEqual(order.last, .indefinite)
        XCTAssertEqual(CaffeinateDuration.indefinite.shortName, "∞")
        for duration in order {
            XCTAssertLessThanOrEqual(duration.shortName.count, 7, duration.shortName)
        }
    }

    func testEveryPopoverHasOneWidth() {
        XCTAssertEqual(DS.panelWidth, 280)
    }

    // MARK: Timer

    func testTheTimerShowsThreePresetsWithShortLabels() {
        XCTAssertEqual(TimerTabLayout.presetCount, 3)
        XCTAssertTrue(TimerTabLayout.presetLabel(300).contains("5"))
        XCTAssertTrue(TimerTabLayout.presetLabel(5400).contains("1"))
        XCTAssertTrue(TimerTabLayout.presetLabel(5400).contains("30"))
        XCTAssertTrue(TimerTabLayout.presetLabel(45).contains("45"))
    }

    func testTheTimerPopoverBecomesTheTab() {
        let saved = Defaults[.timerDisplayMode]
        defer { Defaults[.timerDisplayMode] = saved }
        Defaults[.timerDisplayMode] = .popover
        Defaults.Keys.migrateTimerPopoverToTab()
        XCTAssertEqual(Defaults[.timerDisplayMode], .tab)
        Defaults.Keys.migrateTimerPopoverToTab()
        XCTAssertEqual(Defaults[.timerDisplayMode], .tab)
    }

    // MARK: Drawing

    func testTheKeepAwakePanelDraws() throws {
        let renderer = ImageRenderer(content: CaffeinatePopover().background(DS.Palette.surface).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, DS.panelWidth, accuracy: 1)
        if let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map({ URL(fileURLWithPath: $0) }),
           let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: folder.appendingPathComponent("keep-awake.png"))
        }
    }
}

/// The island and the picture preview are sized by Skerry alone. With the
/// hosting view as the window's contentView, SwiftUI resized the window too
/// when its content grew, and the two re-entered Update Constraints until
/// AppKit threw (crashes 23.10, 09:53 and 10:20).
final class SelfSizedWindowTests: XCTestCase {
    private final class Height: ObservableObject {
        @Published var value: CGFloat = 50
    }

    private struct Root: View {
        @ObservedObject var height: Height
        var body: some View { Color.clear.frame(width: 200, height: height.value) }
    }

    /// The control needs the SwiftUI App lifecycle, which the test host
    /// (Skerry itself) has; without a host app it would fail.
    @MainActor
    func testSwiftUIDoesNotResizeASelfSizedWindow() {
        XCTAssertNotEqual(windowHeightAfterTheContentGrows(selfSized: false), 100,
                          "as contentView the hosting view resizes the window: the test sees it")
        XCTAssertEqual(windowHeightAfterTheContentGrows(selfSized: true), 100)
    }

    @MainActor
    func testTheHostFillsTheWindowAndFollowsItsSize() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSHostingView(rootView: Color.clear)
        window.setSelfSizedContent(host)
        XCTAssertFalse(window.contentView is NSHostingView<Color>)
        XCTAssertTrue(host.superview === window.contentView)
        XCTAssertEqual(host.frame.size, NSSize(width: 200, height: 100))
        window.setContentSize(NSSize(width: 300, height: 150))
        XCTAssertEqual(host.frame.size, NSSize(width: 300, height: 150))

        // The picture preview starts at .zero and is sized from its content.
        // Its own hosting view, with sizingOptions = [], measures 0 × 0: the
        // preview was an empty panel from 1.1.2 to 1.1.4.
        let content = Color.clear.frame(width: 120, height: 80)
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        let preview = NSHostingView(rootView: content)
        preview.sizingOptions = []
        panel.setSelfSizedContent(preview)
        panel.setFrame(NSRect(origin: .zero, size: ClipboardPreviewPanel.measuredSize(of: content)), display: false)
        XCTAssertEqual(preview.frame.size, NSSize(width: 120, height: 80))
    }

    /// Shows a 200 × 100 window (out of sight), grows its content to 300 pt
    /// in an animation, and returns the window's height after it.
    @MainActor
    private func windowHeightAfterTheContentGrows(selfSized: Bool) -> CGFloat {
        let height = Height()
        let window = NSPanel(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 100),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        let host = NSHostingView(rootView: Root(height: height))
        host.sizingOptions = []
        if selfSized {
            window.setSelfSizedContent(host)
        } else {
            window.contentView = host
        }
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.close()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        withAnimation(.linear(duration: 0.1)) { height.value = 300 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if selfSized {
            XCTAssertEqual(host.frame.size, window.contentView?.bounds.size, "the shown window's content fills it")
        }
        return window.frame.height
    }
}
