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
        XCTAssertEqual(BufferFit.maximum, gridTabOpenHeight)
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
