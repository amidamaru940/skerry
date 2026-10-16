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

/// The compact player's progress line seeks: a click or a drag lands at the
/// share of the track under the pointer. It used to be drawn only, so music
/// could not be wound at all in the one-row player.
final class CompactSeekTests: XCTestCase {
    func testThePointerPicksTheShareOfTheTrack() {
        XCTAssertEqual(CompactSeek.fraction(atX: 50, width: 200), 0.25)
        XCTAssertEqual(CompactSeek.fraction(atX: -8, width: 200), 0, "a drag past the start stops at the start")
        XCTAssertEqual(CompactSeek.fraction(atX: 260, width: 200), 1, "and past the end at the end")
        XCTAssertEqual(CompactSeek.fraction(atX: 10, width: 0), 0, "a line not laid out yet seeks nowhere")
    }

    func testTheShareBecomesAPositionInTheTrack() {
        XCTAssertEqual(CompactSeek.position(fraction: 0.25, duration: 360), 90)
        XCTAssertEqual(CompactSeek.position(fraction: 1.4, duration: 360), 360)
        XCTAssertNil(CompactSeek.position(fraction: 0.5, duration: 0), "a live stream has nowhere to seek to")
        XCTAssertNil(CompactSeek.position(fraction: 0.5, duration: 1_732_919_508), "nor does an epoch sent as a length")
        XCTAssertNil(CompactSeek.position(fraction: 0.5, duration: .infinity))
    }

    func testTheLineHoldsWhereItWasDroppedUntilThePlayerCatchesUp() {
        let dropped = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(
            CompactSeek.holdIsOver(reported: 0.10, dropped: 0.60, droppedAt: dropped, now: dropped.addingTimeInterval(0.5)),
            "the old position arriving just after the drop must not pull the line back"
        )
        XCTAssertTrue(CompactSeek.holdIsOver(reported: 0.605, dropped: 0.60, droppedAt: dropped, now: dropped.addingTimeInterval(0.5)))
        XCTAssertTrue(
            CompactSeek.holdIsOver(reported: 0.10, dropped: 0.60, droppedAt: dropped, now: dropped.addingTimeInterval(CompactSeek.holdLimit)),
            "a player that ignored the seek gets the line back"
        )
    }

    func testTheTimeShownWhileDragging() {
        XCTAssertEqual(CompactSeek.timeLabel(fraction: 83.0 / 359.0, duration: 359), "1:23 / 5:59")
        XCTAssertEqual(CompactSeek.timeLabel(fraction: 0, duration: 3723), "0:00 / 1:02:03")
        XCTAssertNil(CompactSeek.timeLabel(fraction: 0.5, duration: 0))
    }

    @MainActor
    func testDrawingTheRowNeverSeeks() {
        let row = CompactPlayerRowContent(
            artwork: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!,
            title: "Song",
            artist: "Artist",
            progress: 0.4,
            isPlaying: true,
            duration: 200,
            onSeek: { _ in XCTFail("drawing must not seek") }
        )
        let host = NSHostingView(rootView: row.frame(width: 640, height: 56))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
