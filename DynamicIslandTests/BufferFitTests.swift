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
import SwiftUI
import XCTest

/// The Clipboard tab is as tall as what it shows. It always opened at the
/// full grid height, so an empty clipboard was a large black square around
/// one line.
final class BufferFitTests: XCTestCase {
    func testAnEmptyClipboardShrinksToAStrip() {
        // 200 points left over under one line at the full height.
        XCTAssertEqual(BufferFit.height(current: 320, slack: 200), BufferFit.minimum)
        XCTAssertEqual(BufferFit.minimum, compactHomeOpenHeight, "as tall as the compact Now tab, so switching tabs does not jump")
    }

    func testOneRowOfCardsGetsJustItsRow() {
        XCTAssertEqual(BufferFit.height(current: 320, slack: 110), 210)
    }

    func testMoreThanFitsKeepsTheFullHeightAndScrolls() {
        XCTAssertEqual(BufferFit.height(current: 320, slack: -240), BufferFit.maximum)
        XCTAssertEqual(BufferFit.maximum, 354, "Buffer v3: the film, its action row and three rows of copies")
    }

    func testANewCopyGrowsTheStripBack() {
        // At 140 the first card overflows by 70.
        XCTAssertEqual(BufferFit.height(current: 140, slack: -70), 210)
    }

    func testTheScreenshotGridAndUnmeasuredContentGetTheFullHeight() {
        XCTAssertEqual(BufferFit.height(current: 140, slack: BufferFit.wantsAllRoom), BufferFit.maximum)
        XCTAssertEqual(BufferFit.height(current: 140, slack: nil), BufferFit.maximum)
    }

    func testMeasuringNoiseDoesNotMoveTheIsland() {
        XCTAssertFalse(BufferFit.isWorthChanging(from: 210, to: 211))
        XCTAssertTrue(BufferFit.isWorthChanging(from: 210, to: 140))
    }

    /// An island fitted to «No copies yet» grows back when the film and its
    /// paste key come in above: the filler reports the overflow, not 0. On
    /// 1.1.2 it reported 0 and the window, no longer grown by SwiftUI, cut
    /// the paste key off (23.10).
    @MainActor
    func testTheFillerSeesContentRunPastTheIsland() {
        XCTAssertEqual(measuredSlack(tab: 150) { Self.fixed(250) } ?? 0, -100, accuracy: 1)
    }

    /// As on the owner's Mac: the overflow is seen through the embedded
    /// history's centred frame, and one fit settles the island.
    @MainActor
    func testOneFitGrowsTheIslandToTheFilmAndSettles() {
        let first = measuredSlack(tab: 152) { Self.filmOverEmptyHistory }
        XCTAssertEqual(first ?? 0, -68, accuracy: 1)
        let fitted = BufferFit.height(current: 152, slack: first)
        XCTAssertEqual(fitted, 220, accuracy: 1)
        let second = measuredSlack(tab: fitted) { Self.filmOverEmptyHistory }
        XCTAssertFalse(BufferFit.isWorthChanging(from: fitted, to: BufferFit.height(current: fitted, slack: second)))
    }

    /// With copies in the history the slack comes from its scroll view. Under
    /// a film that ran past the island the scroll view is squeezed to 0; its
    /// own height made the fit grow by the rows only, and the island stayed
    /// cut until reopened (23.10). One fit settles it now.
    @MainActor
    func testOneFitGrowsTheIslandPastTheFilmToTheHistory() {
        let first = measuredSlack(tab: 152) { Self.filmOverHistory }
        XCTAssertEqual(first ?? 0, -102, accuracy: 1)
        let fitted = BufferFit.height(current: 152, slack: first)
        XCTAssertEqual(fitted, 254, accuracy: 1)
        let second = measuredSlack(tab: fitted) { Self.filmOverHistory }
        XCTAssertFalse(BufferFit.isWorthChanging(from: fitted, to: BufferFit.height(current: fitted, slack: second)))
    }

    /// When the copies leave room below, the island still shrinks to them.
    @MainActor
    func testTheHistoryLeavesItsRoomBelow() {
        XCTAssertEqual(measuredSlack(tab: 300) { Self.filmOverHistory } ?? 0, 46, accuracy: 1)
    }

    @MainActor
    func testTheFillerReportsTheRoomLeftUnderShortContent() {
        XCTAssertEqual(measuredSlack(tab: 200) { Self.fixed(100) } ?? 0, 100, accuracy: 1)
    }

    /// Outside the tab's frame (the standalone clipboard) it reports its own
    /// height, as before.
    @MainActor
    func testOutsideTheTabFrameTheFillerReportsItsHeight() {
        XCTAssertEqual(measuredSlack(tab: 200, framed: false) { Self.fixed(100) } ?? -1, 100, accuracy: 1)
        XCTAssertEqual(measuredSlack(tab: 150, framed: false) { Self.fixed(250) } ?? -1, 0, accuracy: 1)
    }

    private static func fixed(_ height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: height)
            BufferSlackFiller()
        }
    }

    /// The film and its action row (190 pt), then the history the way
    /// `NotchClipboardView` embeds it: «No copies yet» (30 pt) and the filler
    /// in a centred frame.
    private static var filmOverEmptyHistory: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 190)
            VStack(spacing: 0) {
                Color.clear.frame(height: 30)
                BufferSlackFiller()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The film (190 pt), then two rows of copies (64 pt) in a scroll view
    /// that reports its slack the way `NotchClipboardView` does.
    private static var filmOverHistory: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 190)
            HistoryScrollProbe(rows: 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct HistoryScrollProbe: View {
        let rows: CGFloat
        @State private var content: CGFloat = 0

        var body: some View {
            ScrollView {
                Color.clear.frame(height: rows)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { content = $0 }
            }
            .modifier(BufferScrollSlack(contentHeight: content))
        }
    }

    private final class SlackBox { var value: CGFloat? }

    /// What `BufferSlackFiller` reports in `content` laid out in a tab `tab`
    /// points tall, inside `BufferTabFrame` unless `framed` is false.
    @MainActor
    private func measuredSlack<Content: View>(
        tab: CGFloat,
        framed: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> CGFloat? {
        let box = SlackBox()
        let body = content()
        let view = Group {
            if framed {
                body.modifier(BufferTabFrame())
            } else {
                body
            }
        }
        .onPreferenceChange(BufferSlackKey.self) { box.value = $0 }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 300, height: tab)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        // The scroll view's measurements land in @State a pass later.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        return box.value
    }

    @MainActor
    func testTheEmptyStateIsOneLineNotABlock() {
        let state = DSEmptyState(
            symbol: "doc.on.clipboard",
            title: "No copies yet",
            message: "Copy something to see it here",
            inline: true
        )
        let host = NSHostingView(rootView: state.frame(width: 600))
        XCTAssertLessThan(host.fittingSize.height, 44)
    }
}
