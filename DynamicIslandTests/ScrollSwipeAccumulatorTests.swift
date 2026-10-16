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
import XCTest

/// Tracks switched by themselves: the swipe that changes them added up
/// scrolling that was never a swipe. The island fires the skip once the total
/// passes "gestureSensitivity" (200 by default).
final class ScrollSwipeAccumulatorTests: XCTestCase {
    private let skipAt: CGFloat = 200

    /// Feeds one gesture: `began`, the deltas 10 ms apart, `ended`; returns
    /// the largest total the island would have seen.
    private func gesture(
        _ swipe: inout ScrollSwipeAccumulator,
        _ deltas: [(CGFloat, CGFloat)],
        startingAt start: TimeInterval = 0,
        endsOverIsland: Bool = true
    ) -> CGFloat {
        var peak: CGFloat = 0
        func note(_ output: ScrollSwipeAccumulator.Output) {
            if case .began(let v) = output { peak = max(peak, v) }
            if case .changed(let v) = output { peak = max(peak, v) }
        }
        for (index, delta) in deltas.enumerated() {
            note(swipe.feed(deltaX: delta.0, deltaY: delta.1, phase: index == 0 ? .began : .changed,
                            momentumPhase: [], timestamp: start + Double(index) * 0.01, isNearView: true))
        }
        note(swipe.feed(deltaX: 0, deltaY: 0, phase: .ended, momentumPhase: [],
                        timestamp: start + Double(deltas.count) * 0.01, isNearView: endsOverIsland))
        return peak
    }

    func testAPlainSidewaysSwipeSkips() {
        var swipe = ScrollSwipeAccumulator(direction: .left, threshold: 4)
        XCTAssertGreaterThan(gesture(&swipe, Array(repeating: (-12, 1), count: 25)), skipAt)
    }

    func testScrollingAPageDownWithSidewaysDriftNeverSkips() {
        var swipe = ScrollSwipeAccumulator(direction: .left, threshold: 4)
        // 400 events of mostly down, each drifting 2 points to the left: 800
        // points of drift used to be added up.
        XCTAssertEqual(gesture(&swipe, Array(repeating: (-2, 14), count: 400)), 0)
    }

    func testAGestureThatEndedOffTheIslandIsNotCarriedIntoTheNext() {
        var swipe = ScrollSwipeAccumulator(direction: .left, threshold: 4)
        // 190 of a swipe, then the pointer moved off the island before the end.
        _ = gesture(&swipe, Array(repeating: (-10, 0), count: 19), endsOverIsland: false)

        let next = gesture(&swipe, Array(repeating: (-10, 0), count: 3), startingAt: 5)

        XCTAssertLessThan(next, skipAt, "a 30-point nudge must not finish the old swipe")
    }

    func testWheelNudgesFarApartDoNotAddUp() {
        var swipe = ScrollSwipeAccumulator(direction: .left, threshold: 4)
        var peak: CGFloat = 0
        // A mouse wheel: no phases. Forty sideways nudges, a second apart.
        for index in 0..<40 {
            if case .began(let v) = swipe.feed(deltaX: -10, deltaY: 0, phase: [], momentumPhase: [],
                                               timestamp: Double(index), isNearView: true) { peak = max(peak, v) }
            if case .changed(let v) = swipe.feed(deltaX: 0, deltaY: 0, phase: [], momentumPhase: [],
                                                 timestamp: Double(index) + 0.01, isNearView: true) { peak = max(peak, v) }
        }
        XCTAssertLessThan(peak, skipAt)
    }

    func testMomentumNeverCounts() {
        var swipe = ScrollSwipeAccumulator(direction: .left, threshold: 4)
        for index in 0..<50 {
            XCTAssertEqual(swipe.feed(deltaX: -20, deltaY: 0, phase: [], momentumPhase: .changed,
                                      timestamp: Double(index) * 0.01, isNearView: true), .none)
        }
    }

    func testLeavingTheIslandMidSwipeEndsIt() {
        var swipe = ScrollSwipeAccumulator(direction: .left, threshold: 4)
        _ = swipe.feed(deltaX: -10, deltaY: 0, phase: .began, momentumPhase: [], timestamp: 0, isNearView: true)
        XCTAssertTrue(swipe.active)

        XCTAssertEqual(swipe.feed(deltaX: -10, deltaY: 0, phase: .changed, momentumPhase: [], timestamp: 0.01, isNearView: false), .ended(0))
        XCTAssertEqual(swipe.accumulated, 0)
    }

    func testVerticalGesturesAreUnchanged() {
        var pull = ScrollSwipeAccumulator(direction: .down, threshold: 4)
        // A pull down drifting sideways still opens the island.
        XCTAssertGreaterThan(gesture(&pull, Array(repeating: (6, 12), count: 25)), skipAt)
    }
}
