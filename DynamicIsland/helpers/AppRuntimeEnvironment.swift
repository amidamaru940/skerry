/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import Foundation

/// Runtime context flags used to keep the app's launch deterministic on CI.
enum AppRuntimeEnvironment {
    /// `true` only in DEBUG builds launched by XCUITest (`--uitesting`); always false in Release.
    static let isUITesting: Bool = {
        #if DEBUG
        return CommandLine.arguments.contains("--uitesting")
        #else
        return false
        #endif
    }()

    /// `true` while the app is the host of the unit tests (XCTest injects its
    /// bundle into the running app); always false in Release.
    static let isHostingUnitTests: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }()

    /// Whether the app may ask macOS for a permission: Accessibility,
    /// Calendar, Bluetooth, Location, or a folder. Never while it hosts tests.
    /// To macOS the test host is an app of its own, so every test run asked
    /// the person at the Mac again, and an ad-hoc signed host on every build.
    static let mayAskForPermissions: Bool = !isUITesting && !isHostingUnitTests
}
