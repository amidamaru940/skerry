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

import Sparkle

/// Skerry is a personal build of Atoll. Official Atoll releases must never
/// be installed over local changes, so the Sparkle updater is switched off.
enum SoftwareUpdatePolicy {
    /// The only switch for software updates. While false the updater controller
    /// is never created, so no feed is fetched, and every update menu item and
    /// settings section is hidden.
    static let isEnabled = false

    /// Returns a Sparkle controller only when updates are enabled.
    static func makeUpdaterController(delegate: SPUUpdaterDelegate) -> SPUStandardUpdaterController? {
        guard isEnabled else { return nil }
        // Skip Sparkle's launch-time update check during UI testing.
        return SPUStandardUpdaterController(
            startingUpdater: !AppRuntimeEnvironment.isUITesting,
            updaterDelegate: delegate, userDriverDelegate: nil)
    }
}
