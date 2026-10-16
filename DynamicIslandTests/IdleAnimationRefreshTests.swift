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
import XCTest

/// Built-in idle animations were stored with an absolute path into the app,
/// so a moved or renamed app lost them. Each launch points them at this app.
final class IdleAnimationRefreshTests: XCTestCase {
    private let gone = URL(fileURLWithPath: "/Applications/Old Name.app/Contents/Resources/Dog waiting.json")
    private let here = URL(fileURLWithPath: "/Applications/Skerry.app/Contents/Resources/Dog waiting.json")

    func testABuiltInAnimationFollowsTheAppAndKeepsItsId() {
        let id = UUID()
        let stored = [CustomIdleAnimation(id: id, name: "Dog waiting", source: .lottieFile(gone), speed: 1.5, isBuiltIn: true)]
        let bundled = [CustomIdleAnimation(name: "Dog waiting", source: .lottieFile(here), isBuiltIn: true)]

        let refreshed = IdleAnimationManager.refreshingBuiltInSources(of: stored, from: bundled)

        XCTAssertEqual(refreshed.first?.source, .lottieFile(here))
        XCTAssertEqual(refreshed.first?.id, id, "its adjustments are stored under the id")
        XCTAssertEqual(refreshed.first?.speed, 1.5)
    }

    func testImportedAnimationsAndUnknownNamesAreLeftAlone() {
        let imported = CustomIdleAnimation(name: "Dog waiting", source: .lottieFile(gone), isBuiltIn: false)
        let retired = CustomIdleAnimation(name: "Retired", source: .lottieFile(gone), isBuiltIn: true)
        let bundled = [CustomIdleAnimation(name: "Dog waiting", source: .lottieFile(here), isBuiltIn: true)]

        let refreshed = IdleAnimationManager.refreshingBuiltInSources(of: [imported, retired], from: bundled)

        XCTAssertEqual(refreshed, [imported, retired])
    }
}
