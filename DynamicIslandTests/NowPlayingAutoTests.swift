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
import Combine
import Defaults
import XCTest

/// The Auto music source: priority and ignored apps.
final class AutoSourceResolverTests: XCTestCase {
    private let safari = "com.apple.Safari"
    private let chrome = "com.google.Chrome"
    private let spotify = AutoMediaSource.spotifyBundleID
    private let music = AutoMediaSource.appleMusicBundleID
    private let order = AutoMediaSource.defaultOrder

    private func choose(
        system: String?, playing: Bool = true,
        spotifyPlaying: Bool = false, musicPlaying: Bool = false,
        order: [AutoMediaSource]? = nil, ignored: Set<String> = []
    ) -> AutoSourceChoice {
        AutoSourceResolver.choose(
            systemApp: system, systemPlaying: playing,
            dedicatedPlaying: [.spotify: spotifyPlaying, .appleMusic: musicPlaying],
            order: order ?? self.order, ignored: ignored
        )
    }

    func testDefaults() {
        XCTAssertEqual(Defaults.Keys.mediaController.defaultValue, .auto)
        XCTAssertEqual(Defaults.Keys.autoMediaSourceOrder.defaultValue, [.spotify, .appleMusic, .otherApps])
        XCTAssertEqual(Defaults.Keys.autoMediaIgnoredApps.defaultValue, [])
    }

    func testWhateverPlaysIsShown() {
        XCTAssertEqual(choose(system: safari), .system)
        XCTAssertEqual(choose(system: spotify), .system)   // macOS reports it: no second controller needed
        XCTAssertEqual(choose(system: nil), .none)
    }

    func testAnIgnoredBrowserIsNotShownAndTheNextPlayerIs() {
        XCTAssertEqual(choose(system: safari, ignored: [safari]), .none)
        XCTAssertEqual(choose(system: safari, spotifyPlaying: true, ignored: [safari]), .dedicated(.spotify))
        XCTAssertEqual(choose(system: chrome, musicPlaying: true, ignored: [safari, chrome]), .dedicated(.appleMusic))
    }

    func testThePriorityDecidesBetweenPlayers() {
        // Spotify is above browsers by default.
        XCTAssertEqual(choose(system: safari, spotifyPlaying: true), .dedicated(.spotify))
        // Browsers first: the browser wins.
        let browsersFirst = AutoSourceResolver.move(.otherApps, onto: .spotify, in: order)
        XCTAssertEqual(choose(system: safari, spotifyPlaying: true, order: browsersFirst), .system)
        // Spotify and Apple Music both play; macOS reports Music.
        XCTAssertEqual(choose(system: music, spotifyPlaying: true), .dedicated(.spotify))
        let musicFirst = AutoSourceResolver.move(.appleMusic, onto: .spotify, in: order)
        XCTAssertEqual(choose(system: music, spotifyPlaying: true, order: musicFirst), .system)
    }

    func testIgnoringSpotifyHidesItEverywhere() {
        XCTAssertEqual(choose(system: safari, spotifyPlaying: true, ignored: [spotify]), .system)
        XCTAssertEqual(choose(system: spotify, ignored: [spotify]), .none)
    }

    func testAPausedPlayerStaysUnlessIgnored() {
        XCTAssertEqual(choose(system: music, playing: false), .system)
        XCTAssertEqual(choose(system: safari, playing: false, ignored: [safari]), .none)
        // A playing player beats a paused one.
        XCTAssertEqual(choose(system: safari, playing: false, spotifyPlaying: true), .dedicated(.spotify))
    }

    func testOrderNormalizationAndMove() {
        XCTAssertEqual(AutoSourceResolver.normalizedOrder([.otherApps, .otherApps]), [.otherApps, .spotify, .appleMusic])
        XCTAssertEqual(AutoSourceResolver.move(.otherApps, onto: .spotify, in: order), [.otherApps, .spotify, .appleMusic])
        XCTAssertEqual(AutoMediaSource.source(for: spotify), .spotify)
        XCTAssertEqual(AutoMediaSource.source(for: music), .appleMusic)
        XCTAssertEqual(AutoMediaSource.source(for: safari), .otherApps)
        XCTAssertTrue(AutoMediaSource.browserBundleIDs.contains(safari))
        XCTAssertTrue(AutoMediaSource.browserBundleIDs.contains(chrome))
    }
}

/// The Auto controller with fake Spotify and Apple Music (no AppleScript, no
/// system Now Playing process). Restores the setting it touches.
final class AutoMediaControllerTests: XCTestCase {
    private var savedIgnored: [String] = []

    override func setUp() {
        super.setUp()
        savedIgnored = Defaults[.autoMediaIgnoredApps]
        Defaults[.autoMediaIgnoredApps] = []
    }

    override func tearDown() {
        Defaults[.autoMediaIgnoredApps] = savedIgnored
        super.tearDown()
    }

    private func musicInfo(playing: Bool) -> AppleMusicPlaybackInfo {
        AppleMusicPlaybackInfo(isPlaying: playing, title: "Test Song", artist: "Test Artist", album: "Test Album",
                               currentTime: 0, duration: 180, isShuffled: false, repeatMode: .off, artwork: Data("art".utf8))
    }

    private func waitForState(_ controller: AutoMediaController, where condition: @escaping (PlaybackState) -> Bool) async {
        let reached = expectation(description: "state")
        let cancellable = controller.playbackStatePublisher.sink { if condition($0) { reached.fulfill() } }
        await fulfillment(of: [reached], timeout: 2)
        cancellable.cancel()
    }

    func testShowsAppleMusicAndHidesItOnceIgnored() async {
        let appleMusic = AppleMusicController(startsObservers: false, playbackInfoProvider: { [self] in musicInfo(playing: true) })
        let spotify = SpotifyController(startsObservers: false, playbackInfoFetcher: { nil })
        let controller = AutoMediaController(system: nil, spotify: spotify, appleMusic: appleMusic)

        XCTAssertEqual(controller.playbackState, AutoMediaController.nothingPlaying)
        await appleMusic.updatePlaybackInfo()
        await waitForState(controller) { $0.title == "Test Song" && $0.isPlaying }
        XCTAssertEqual(controller.choice, .dedicated(.appleMusic))

        Defaults[.autoMediaIgnoredApps] = [AutoMediaSource.appleMusicBundleID]
        await waitForState(controller) { $0 == AutoMediaController.nothingPlaying }
        XCTAssertEqual(controller.choice, .none)
    }

    func testNothingPlayingLooksIdle() {
        let state = AutoMediaController.nothingPlaying
        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.title.isEmpty && state.artist.isEmpty)
    }
}

/// Player defaults: wait after pause, sounds, lyrics consent, control slots.
/// Lyrics are never actually turned on here (that could send a request).
@MainActor
final class NowPlayingDefaultsTests: XCTestCase {
    func testMusicStaysTenSecondsAfterPause() {
        XCTAssertEqual(Defaults.Keys.waitInterval.defaultValue, 10)
    }

    func testSoundsAreOffExceptTheTimer() {
        XCTAssertFalse(Defaults.Keys.enableLockSounds.defaultValue)
        XCTAssertFalse(Defaults.Keys.playLowBatteryAlertSound.defaultValue)
        XCTAssertFalse(Defaults.Keys.playWelcomeSound.defaultValue)
        XCTAssertTrue(Defaults.Keys.showPlayerVolumeRow.defaultValue)
    }

    func testLyricsAskBeforeTurningOn() {
        var asked = 0
        let no = { asked += 1; return false }
        let yes = { asked += 1; return true }

        XCTAssertFalse(LyricsConsent.resolve(requested: true, currentlyOn: false, confirm: no))
        XCTAssertTrue(LyricsConsent.resolve(requested: true, currentlyOn: false, confirm: yes))
        XCTAssertEqual(asked, 2)
        // Turning off, or "on" while already on, never asks.
        XCTAssertFalse(LyricsConsent.resolve(requested: false, currentlyOn: true, confirm: no))
        XCTAssertTrue(LyricsConsent.resolve(requested: true, currentlyOn: true, confirm: no))
        XCTAssertEqual(asked, 2)
        XCTAssertTrue(LyricsConsent.explanation.contains("lrclib.net") && LyricsConsent.explanation.contains("music.163.com"))
    }

    func testAFreshInstallKeepsRepeatInTheLastSlot() {
        XCTAssertFalse(Defaults.Keys.migratesAuxToMediaOutput(storedShowMediaOutputControl: nil))
        XCTAssertFalse(Defaults.Keys.migratesAuxToMediaOutput(storedShowMediaOutputControl: false))
        XCTAssertTrue(Defaults.Keys.migratesAuxToMediaOutput(storedShowMediaOutputControl: true))
        XCTAssertEqual(MusicControlButton.defaultLayout, [.shuffle, .trackBackward, .playPause, .trackForward, .repeatMode])
    }
}
