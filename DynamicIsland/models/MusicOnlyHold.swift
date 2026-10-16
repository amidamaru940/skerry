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

import Foundation

/// Keeps the player on music while a video without track details holds the
/// system's playback controls.
///
/// A browser hands macOS one of its tabs at a time: the one that started
/// playing last. Scrolling Instagram Reels in one tab while music played in
/// another made the island show the Reel, and seek it. Such a video carries
/// the page's title for a name ("Instagram • Сообщения") and no artist or
/// album, so it is told apart by that. It is not shown: the music stays on
/// screen, its controls on hold because they would reach the video, until the
/// browser hands the controls back -- which it does when the video is closed.
/// With no music before it, the video is not shown at all.
struct MusicOnlyHold {
    /// Why the previous track is still on screen while a report arrives.
    enum Settling: Equatable {
        /// The system reported nothing: a browser does, for about a second,
        /// between one track and the next.
        case gap
        /// A new title over the previous track's artist, album and length.
        case halfArrived
        /// A title alone, without artist, album or length yet.
        case titleOnly
        /// A new track whose artwork follows a moment later.
        case artwork
    }

    static func limit(for reason: Settling) -> TimeInterval {
        switch reason {
        case .gap, .titleOnly: return 2.5
        case .halfArrived: return 1.5
        case .artwork: return 0.5
        }
    }

    /// Players whose tracks are music even when untagged: a local file with
    /// no artist or album must not be taken for a video.
    static let musicApps: Set<String> = [
        AppleMusicFavoriting.bundleIdentifier,
        SpotifyController.bundleIdentifier,
        TidalController.bundleIdentifier,
        AmazonMusicController.bundleIdentifier,
        CiderController.bundleIdentifier,
        YouTubeMusicFavoriting.bundleIdentifier,
    ]

    /// The last music reported, kept on screen while a video holds the
    /// controls or the next track is still arriving.
    private(set) var lastMusic: PlaybackState?
    private(set) var settling: (reason: Settling, since: Date)?

    var isSettling: Bool { settling != nil }

    /// When to look again if nothing more arrives.
    var settleDeadline: Date? {
        settling.map { $0.since.addingTimeInterval(Self.limit(for: $0.reason)) }
    }

    /// A video with no track details: a title and a length, but no artist and
    /// no album.
    static func isUntitledVideo(_ state: PlaybackState) -> Bool {
        !isBlank(state.title)
            && isBlank(state.artist)
            && isBlank(state.album)
            && state.duration > 0
            && !musicApps.contains(state.bundleIdentifier)
    }

    /// A switch that has arrived only in part: a new title over the previous
    /// track's artist, album and length. A browser moving to another tab
    /// publishes the title first, so for a moment the Reel's page title
    /// appeared under the song's artist.
    static func isHalfArrivedSwitch(_ state: PlaybackState, from previous: PlaybackState) -> Bool {
        state.bundleIdentifier == previous.bundleIdentifier
            && state.title != previous.title
            && !isBlank(previous.artist)
            && state.artist == previous.artist
            && state.album == previous.album
            && state.duration == previous.duration
    }

    /// Whether this report is a track still arriving, to be waited for with
    /// the previous one on screen. Measured on a browser's track change: about
    /// 1.3 s of nothing, then the title alone, then everything else, then the
    /// artwork -- and the player disappeared and redrew itself for each.
    static func settling(_ state: PlaybackState, after previous: PlaybackState) -> Settling? {
        if isBlank(state.title) { return .gap }
        if isHalfArrivedSwitch(state, from: previous) { return .halfArrived }
        if isBlank(state.artist), isBlank(state.album), state.duration <= 0,
           !musicApps.contains(state.bundleIdentifier) {
            return .titleOnly
        }
        let isNewTrack = state.title != previous.title || state.artist != previous.artist
        if isNewTrack, state.artwork == nil { return .artwork }
        return nil
    }

    /// What to show for a state reported by the system.
    mutating func admit(_ state: PlaybackState, now: Date) -> PlaybackState {
        if Self.isUntitledVideo(state) {
            settling = nil
            guard var held = lastMusic else { return Self.nothingPlaying(from: state) }
            held.controlsTakenBy = state.bundleIdentifier
            return held
        }

        if let last = lastMusic, let reason = Self.settling(state, after: last) {
            let since = settling?.reason == reason ? settling!.since : now
            if now.timeIntervalSince(since) < Self.limit(for: reason) {
                settling = (reason, since)
                return last
            }
        }
        settling = nil

        lastMusic = Self.isBlank(state.title) ? nil : state
        return state
    }

    static func nothingPlaying(from state: PlaybackState) -> PlaybackState {
        PlaybackState(bundleIdentifier: state.bundleIdentifier, isPlaying: false, title: "", artist: "", album: "")
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
