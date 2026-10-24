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

/// Launch resumes what a crashed Skerry left frozen. The test host did it
/// too, and unfroze the OSDUIHelper the installed Skerry had frozen: the
/// system HUD came up next to Skerry's until the helper restarted.
final class LaunchRecoveryGateTests: XCTestCase {
    private let own: pid_t = 100
    private let other: pid_t = 200

    func testTheTestHostDoesNotRecover() {
        XCTAssertFalse(LaunchRecoveryGate.recovers(hostingUnitTests: true, skerryPIDs: [own], ownPID: own))
        XCTAssertFalse(LaunchRecoveryGate.recovers(hostingUnitTests: true, skerryPIDs: [], ownPID: own))
    }

    func testAnotherRunningSkerryStopsTheRecovery() {
        XCTAssertFalse(LaunchRecoveryGate.recovers(hostingUnitTests: false, skerryPIDs: [own, other], ownPID: own))
        XCTAssertFalse(LaunchRecoveryGate.recovers(hostingUnitTests: false, skerryPIDs: [other], ownPID: own),
                       "this process not listed yet")
    }

    func testTheOnlySkerryRecovers() {
        XCTAssertTrue(LaunchRecoveryGate.recovers(hostingUnitTests: false, skerryPIDs: [own], ownPID: own))
        XCTAssertTrue(LaunchRecoveryGate.recovers(hostingUnitTests: false, skerryPIDs: [], ownPID: own),
                      "this process not listed yet")
    }

    /// The host is the Debug build: its bundle identifier is one the gate
    /// looks for, and its own launch did not recover.
    func testThisHostIsSeenAndDoesNotRecover() {
        XCTAssertTrue(LaunchRecoveryGate.bundleIdentifiers.contains(Bundle.main.bundleIdentifier ?? ""))
        XCTAssertFalse(LaunchRecoveryGate.recoversAtThisLaunch)
    }
}

/// Music's AirPlay list, read without Music: its script answers {} on an
/// error, and the range 1...0 over that answer trapped.
final class AirPlayDeviceListTests: XCTestCase {
    func testAnEmptyAnswerIsNoDevices() {
        XCTAssertEqual(AppleMusicAirPlayManager.devices(from: .list()), [])
        XCTAssertEqual(AppleMusicAirPlayManager.devices(from: .null()), [])
    }

    func testEachListIsADevice() {
        let answer = NSAppleEventDescriptor.list()
        answer.insert(device("Kitchen", "HomePod", selected: true, address: "AA:BB", volume: 40), at: 1)
        answer.insert(device("Mac", "computer", selected: false, address: "", volume: 75), at: 2)

        XCTAssertEqual(AppleMusicAirPlayManager.devices(from: answer), [
            AirPlayDevice(id: "AA:BB", name: "Kitchen", kind: "HomePod", isSelected: true, volume: 40),
            AirPlayDevice(id: "Mac", name: "Mac", kind: "computer", isSelected: false, volume: 75),
        ])
    }

    private func device(_ name: String, _ kind: String, selected: Bool, address: String, volume: Int32) -> NSAppleEventDescriptor {
        let item = NSAppleEventDescriptor.list()
        item.insert(NSAppleEventDescriptor(string: name), at: 1)
        item.insert(NSAppleEventDescriptor(string: kind), at: 2)
        item.insert(NSAppleEventDescriptor(boolean: selected), at: 3)
        item.insert(NSAppleEventDescriptor(string: address), at: 4)
        item.insert(NSAppleEventDescriptor(int32: volume), at: 5)
        return item
    }
}
