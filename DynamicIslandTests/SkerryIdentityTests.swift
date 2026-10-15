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

/// Checks the built host app: fork identity, no Sparkle feed, no updater.
final class SkerryIdentityTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    func testHostAppUsesForkIdentity() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        XCTAssertTrue(["io.github.amidamaru940.skerry", "io.github.amidamaru940.skerry.dev"].contains(bundleID), bundleID)
        XCTAssertEqual(info["CFBundleName"] as? String, "Skerry")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Skerry")
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "Skerry")
    }

    func testTestBundleUsesForkIdentifier() {
        XCTAssertEqual(Bundle(for: Self.self).bundleIdentifier, "io.github.amidamaru940.skerry.tests")
    }

    func testBuiltInfoPlistHasNoSparkleFeed() {
        for key in ["SUFeedURL", "SUPublicEDKey", "SUEnableDownloaderService", "SUEnableInstallerLauncherService"] {
            XCTAssertNil(info[key], "\(key) must not be in the built Info.plist")
        }
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, false)
    }

    @MainActor
    func testUpdaterIsNeverCreated() {
        XCTAssertFalse(SoftwareUpdatePolicy.isEnabled)
        XCTAssertNil(SoftwareUpdatePolicy.makeUpdaterController(delegate: AtollUpdaterDelegate()))
        // The running host app went through DynamicNotchApp.init(); no updater may have been handed over.
        XCTAssertFalse(SettingsWindowController.shared.hasUpdaterController)
    }

    func testSignedAppHasNoCameraEntitlement() throws {
        let task = try XCTUnwrap(SecTaskCreateFromSelf(nil))
        let camera = SecTaskCopyValueForEntitlement(task, "com.apple.security.device.camera" as CFString, nil)
        XCTAssertNil(camera, "the signed host app must not carry the camera entitlement")
        // Sanity check that entitlements are readable at all.
        let appleEvents = SecTaskCopyValueForEntitlement(task, "com.apple.security.automation.apple-events" as CFString, nil)
        XCTAssertEqual(appleEvents as? Bool, true)
    }

    func testUsageDescriptionsNameTheFork() {
        let usage = info.filter { $0.key.hasSuffix("UsageDescription") }
        XCTAssertFalse(usage.isEmpty)
        for (key, value) in usage {
            XCTAssertFalse((value as? String ?? "").contains("Atoll"), "\(key) still says Atoll")
        }
    }
}
