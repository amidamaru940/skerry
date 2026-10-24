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

/// The island stays on music: a video without track details (Instagram Reels
/// in a browser tab) does not take the player over. Built from what the system
/// reported, in order, while a Reel was opened over music in another tab.
final class MusicOnlyHoldTests: XCTestCase {
    private let browser = "com.google.Chrome"
    private let start = Date(timeIntervalSince1970: 1_000)

    private func music(_ title: String = "Song", artist: String = "Artist", duration: Double = 210.4, artwork: Data? = Data([1])) -> PlaybackState {
        PlaybackState(bundleIdentifier: browser, isPlaying: true, title: title, artist: artist, album: "Tracks", duration: duration, artwork: artwork)
    }

    private func reel(_ title: String = "Instagram • Messages") -> PlaybackState {
        PlaybackState(bundleIdentifier: browser, isPlaying: true, title: title, artist: "", album: "", duration: 58.7)
    }

    func testAReelKeepsTheMusicOnScreenWithItsControlsOnHold() {
        var hold = MusicOnlyHold()
        XCTAssertEqual(hold.admit(music(), now: start), music())

        let shown = hold.admit(reel(), now: start.addingTimeInterval(60))

        XCTAssertEqual(shown.title, "Song")
        XCTAssertEqual(shown.artist, "Artist")
        XCTAssertTrue(shown.isPlaying, "the music plays on in its own tab")
        XCTAssertEqual(shown.controlsTakenBy, browser, "a command now would reach the Reel")
    }

    func testClosingTheReelGivesTheControlsBack() {
        var hold = MusicOnlyHold()
        _ = hold.admit(music(), now: start)
        _ = hold.admit(reel(), now: start.addingTimeInterval(1))
        // The browser hands the slot back title first, over the Reel's blanks.
        let halfBack = PlaybackState(bundleIdentifier: browser, isPlaying: true, title: "Song", artist: "", album: "", duration: 58.7)
        XCTAssertEqual(hold.admit(halfBack, now: start.addingTimeInterval(40)).controlsTakenBy, browser)

        let shown = hold.admit(music(), now: start.addingTimeInterval(41))

        XCTAssertEqual(shown, music())
        XCTAssertNil(shown.controlsTakenBy)
    }

    /// An episode on a series site reports no artist either, but runs far
    /// longer than a Reel: it is shown and the island controls it (23.10).
    func testALongVideoWithoutArtistIsShownWithItsControls() {
        let episode = PlaybackState(bundleIdentifier: browser, isPlaying: true, title: "Смотреть Сериал 33 серия", artist: "", album: "", duration: 1377.4, artwork: Data([2]))
        var hold = MusicOnlyHold()
        _ = hold.admit(music(), now: start)

        let shown = hold.admit(episode, now: start.addingTimeInterval(60))

        XCTAssertEqual(shown, episode)
        XCTAssertNil(shown.controlsTakenBy)

        var fresh = MusicOnlyHold()
        XCTAssertEqual(fresh.admit(episode, now: start), episode, "with no music before it too")
        XCTAssertFalse(MusicOnlyHold.isUntitledVideo(episode))
        XCTAssertTrue(MusicOnlyHold.isUntitledVideo(reel()), "a Reel is still held")
    }

    /// A Reel opened over a paused episode arrives title first, over the
    /// episode's blank artist, length and cover: that mix is not shown, and
    /// the Reel then holds the episode like music.
    func testAReelOverAnEpisodeArrivingTitleFirstIsNotShown() {
        let episode = PlaybackState(bundleIdentifier: browser, isPlaying: false, title: "Сериал 33 серия", artist: "", album: "", duration: 1377.4, artwork: Data([2]))
        var hold = MusicOnlyHold()
        XCTAssertEqual(hold.admit(episode, now: start), episode)

        let titleFirst = PlaybackState(bundleIdentifier: browser, isPlaying: true, title: "Instagram • Messages", artist: "", album: "", duration: 1377.4, artwork: Data([2]))
        XCTAssertEqual(hold.admit(titleFirst, now: start.addingTimeInterval(10)).title, "Сериал 33 серия")

        let shown = hold.admit(reel(), now: start.addingTimeInterval(10.4))
        XCTAssertEqual(shown.title, "Сериал 33 серия")
        XCTAssertEqual(shown.controlsTakenBy, browser)
    }

    /// Recorded 23.10: Chrome moving from a paused YouTube video to
    /// a series tab sent the episode's title over the video's channel,
    /// length and cover, then the episode alone, then its cover.
    func testSwitchingFromYouTubeToASeriesTabShowsTheEpisode() {
        let youtube = PlaybackState(bundleIdentifier: browser, isPlaying: false, title: "\"Разговор\" — интервью", artist: "Anchor", album: "", duration: 446.96, artwork: Data([1]))
        var hold = MusicOnlyHold()
        XCTAssertEqual(hold.admit(youtube, now: start), youtube)

        var mix = youtube
        mix.title = "Смотреть Сериал 33 серия"
        mix.artwork = nil
        XCTAssertEqual(hold.admit(mix, now: start.addingTimeInterval(10)).title, youtube.title)
        mix.artwork = Data([1])
        mix.isPlaying = true
        XCTAssertEqual(hold.admit(mix, now: start.addingTimeInterval(10.1)).title, youtube.title)

        var episode = PlaybackState(bundleIdentifier: browser, isPlaying: true, title: mix.title, artist: "", album: "", duration: 1377.4)
        _ = hold.admit(episode, now: start.addingTimeInterval(10.2))
        episode.artwork = Data([2])
        let shown = hold.admit(episode, now: start.addingTimeInterval(10.3))

        XCTAssertEqual(shown, episode)
        XCTAssertNil(shown.controlsTakenBy)
    }

    func testFiveMinutesIsWhereAVideoStopsBeingAClip() {
        let clip = PlaybackState(bundleIdentifier: browser, isPlaying: true, title: "Clip", artist: "", album: "", duration: 299.9)
        let video = PlaybackState(bundleIdentifier: browser, isPlaying: true, title: "Video", artist: "", album: "", duration: 300)
        XCTAssertTrue(MusicOnlyHold.isUntitledVideo(clip))
        XCTAssertFalse(MusicOnlyHold.isUntitledVideo(video))
    }

    func testAReelWithNoMusicBeforeItIsNotShown() {
        var hold = MusicOnlyHold()

        let shown = hold.admit(reel(), now: start)

        XCTAssertEqual(shown.title, "")
        XCTAssertFalse(shown.isPlaying)
        XCTAssertNil(shown.controlsTakenBy)
    }

    func testThePageTitleNeverAppearsUnderTheSongsArtist() {
        var hold = MusicOnlyHold()
        _ = hold.admit(music(), now: start)
        // The switch arrived title first: the Reel's page title over the song's
        // artist, album and length.
        var halfArrived = music()
        halfArrived.title = "Instagram • Messages"

        XCTAssertEqual(hold.admit(halfArrived, now: start.addingTimeInterval(0.1)).title, "Song")
        XCTAssertTrue(hold.isSettling)
        let held = hold.admit(reel(), now: start.addingTimeInterval(0.2))

        XCTAssertEqual(held.title, "Song", "the hold keeps the song, not the half-arrived mix")
        XCTAssertEqual(held.controlsTakenBy, browser)
    }

    func testAHalfArrivedSwitchThatNeverCompletesIsShownInTime() {
        var hold = MusicOnlyHold()
        _ = hold.admit(music(), now: start)
        var sameArtistAndLength = music()
        sameArtistAndLength.title = "Another Song"
        _ = hold.admit(sameArtistAndLength, now: start)

        let shown = hold.admit(sameArtistAndLength, now: start.addingTimeInterval(MusicOnlyHold.limit(for: .halfArrived)))

        XCTAssertEqual(shown.title, "Another Song")
        XCTAssertFalse(hold.isSettling)
    }

    func testTheNextTrackByTheSameArtistShowsAtOnce() {
        var hold = MusicOnlyHold()
        _ = hold.admit(music(), now: start)

        let next = music("Next Song", duration: 187.2)

        XCTAssertEqual(hold.admit(next, now: start.addingTimeInterval(1)), next)
        XCTAssertFalse(hold.isSettling)
    }

    func testAnUntaggedFileInAMusicAppIsMusic() {
        var hold = MusicOnlyHold()
        let untagged = PlaybackState(bundleIdentifier: AppleMusicFavoriting.bundleIdentifier, isPlaying: true, title: "track01", artist: "", album: "")

        XCTAssertFalse(MusicOnlyHold.isUntitledVideo(untagged))
        XCTAssertEqual(hold.admit(untagged, now: start), untagged)
    }

    func testMusicThatStoppedIsNotHeldForALaterReel() {
        var hold = MusicOnlyHold()
        _ = hold.admit(music(), now: start)
        // The music tab was closed: the system reports nothing playing.
        let nothing = PlaybackState(bundleIdentifier: "", isPlaying: false, title: "", artist: "", album: "")
        _ = hold.admit(nothing, now: start.addingTimeInterval(5))
        _ = hold.admit(nothing, now: start.addingTimeInterval(5 + MusicOnlyHold.limit(for: .gap)))

        let shown = hold.admit(reel(), now: start.addingTimeInterval(10))

        XCTAssertEqual(shown.title, "")
        XCTAssertNil(shown.controlsTakenBy)
    }

    /// A browser's track change as recorded: about 1.3 s of nothing, the
    /// title alone, everything but the artwork, then the artwork.
    func testTheNextTrackReplacesThePreviousOneWithoutAGap() {
        var hold = MusicOnlyHold()
        _ = hold.admit(music(), now: start)
        let nothing = PlaybackState(bundleIdentifier: browser, isPlaying: false, title: "", artist: "", album: "")
        let titleOnly = PlaybackState(bundleIdentifier: browser, isPlaying: true, title: "Next Song", artist: "", album: "")
        let noArtworkYet = music("Next Song", artist: "Next Artist", duration: 394.6, artwork: nil)
        let complete = music("Next Song", artist: "Next Artist", duration: 394.6, artwork: Data([2]))

        XCTAssertEqual(hold.admit(nothing, now: start.addingTimeInterval(0.1)), music(), "the player must not disappear")
        XCTAssertEqual(hold.admit(titleOnly, now: start.addingTimeInterval(1.4)), music(), "nor show a title with nothing under it")
        XCTAssertEqual(hold.admit(noArtworkYet, now: start.addingTimeInterval(1.9)), music(), "nor change twice for the artwork")
        XCTAssertEqual(hold.admit(complete, now: start.addingTimeInterval(1.91)), complete)
        XCTAssertFalse(hold.isSettling)
    }

    func testATrackWithoutArtworkStillShowsAfterAMoment() {
        var hold = MusicOnlyHold()
        _ = hold.admit(music(), now: start)
        let artless = music("Next Song", artist: "Next Artist", duration: 187.2, artwork: nil)

        XCTAssertEqual(hold.admit(artless, now: start.addingTimeInterval(1)).title, "Song")
        XCTAssertEqual(hold.settleDeadline, start.addingTimeInterval(1 + MusicOnlyHold.limit(for: .artwork)))
        XCTAssertEqual(hold.admit(artless, now: hold.settleDeadline!), artless)
    }

    func testMusicThatEndsIsGoneAfterTheGap() {
        var hold = MusicOnlyHold()
        _ = hold.admit(music(), now: start)
        let nothing = PlaybackState(bundleIdentifier: browser, isPlaying: false, title: "", artist: "", album: "")
        _ = hold.admit(nothing, now: start.addingTimeInterval(1))

        let shown = hold.admit(nothing, now: hold.settleDeadline!)

        XCTAssertEqual(shown.title, "")
        XCTAssertNil(hold.lastMusic)
    }

    func testAHoldIsAChangeThePlayerHears() {
        var held = music()
        held.controlsTakenBy = browser
        XCTAssertNotEqual(held, music(), "otherwise the controls would never dim")
    }

    func testTheNoteNamesTheAppThatHasTheControls() {
        XCTAssertEqual(MusicManager.appName(for: "com.apple.finder"), "Finder")
        XCTAssertEqual(MusicManager.appName(for: "org.example.not-installed"), "org.example.not-installed")
    }
}
