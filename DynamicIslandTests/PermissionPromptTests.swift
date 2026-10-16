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

/// To macOS the unit-test host is an app of its own, so whatever it asked
/// for at launch -- Accessibility, Calendar, Bluetooth, the keyboard tap --
/// came up on screen on every test run.
final class PermissionPromptTests: XCTestCase {
    func testTheTestHostNeverAsksForPermissions() {
        XCTAssertTrue(AppRuntimeEnvironment.isHostingUnitTests)
        XCTAssertFalse(AppRuntimeEnvironment.mayAskForPermissions)
    }

    func testTheMediaKeyTapIsNotInstalledUnderTests() {
        XCTAssertFalse(MediaKeyInterceptor.shared.start())
    }

    /// The test host's island took the keyboard from the chat the person was
    /// typing in, and showed a second island over the real one.
    @MainActor
    func testTheTestHostsIslandIsNeverShownNorKey() {
        let window = DynamicIslandWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.isKeyWindow)
    }
}
