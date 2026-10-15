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

import Combine
import Defaults
import Foundation

/// The Auto music source: shows whatever plays, by the user's priority and
/// ignore list (see `AutoSourceResolver`).
///
/// The system Now Playing (all apps, browsers included, no permission
/// needed) is the base. Spotify and Apple Music also run their own
/// controllers, so one of them can be shown while macOS reports another app
/// that is ignored or lower in the list. Controls go to the player shown.
final class AutoMediaController: ObservableObject, MediaControllerProtocol {
    @Published private(set) var playbackState = AutoMediaController.nothingPlaying
    @Published private(set) var choice: AutoSourceChoice = .none

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    /// Nil when the system Now Playing does not work on this macOS.
    private let system: NowPlayingController?
    private let spotify: SpotifyController
    private let appleMusic: AppleMusicController

    private var systemState: PlaybackState?
    private var spotifyState: PlaybackState?
    private var appleMusicState: PlaybackState?
    private var cancellables = Set<AnyCancellable>()

    /// No title or artist: the island treats it as nothing playing.
    static let nothingPlaying = PlaybackState(bundleIdentifier: "", isPlaying: false, title: "", artist: "", album: "")

    init(system: NowPlayingController?, spotify: SpotifyController = SpotifyController(), appleMusic: AppleMusicController = AppleMusicController()) {
        self.system = system
        self.spotify = spotify
        self.appleMusic = appleMusic

        // Each controller starts with a placeholder track; only its own
        // reports (after the first, replayed value) count.
        system?.playbackStatePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.systemState = state
                self?.reselect()
            }
            .store(in: &cancellables)
        spotify.playbackStatePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.spotifyState = state
                self?.reselect()
            }
            .store(in: &cancellables)
        appleMusic.playbackStatePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.appleMusicState = state
                self?.reselect()
            }
            .store(in: &cancellables)

        Defaults.publisher(keys: .autoMediaSourceOrder, .autoMediaIgnoredApps, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reselect() }
            .store(in: &cancellables)
    }

    private func reselect() {
        let newChoice = AutoSourceResolver.choose(
            systemApp: systemState?.bundleIdentifier,
            systemPlaying: systemState?.isPlaying ?? false,
            dedicatedPlaying: [
                .spotify: spotifyState?.isPlaying ?? false,
                .appleMusic: appleMusicState?.isPlaying ?? false,
            ],
            order: Defaults[.autoMediaSourceOrder],
            ignored: Set(Defaults[.autoMediaIgnoredApps])
        )
        if newChoice != choice { choice = newChoice }

        let state: PlaybackState?
        switch newChoice {
        case .system: state = systemState
        case .dedicated(.spotify): state = spotifyState
        case .dedicated(.appleMusic): state = appleMusicState
        case .dedicated(.otherApps), .none: state = nil
        }
        let shown = state ?? Self.nothingPlaying
        if shown != playbackState { playbackState = shown }
    }

    /// The controller of the player shown; the system one when nothing is.
    private var target: (any MediaControllerProtocol)? {
        switch choice {
        case .dedicated(.spotify): return spotify
        case .dedicated(.appleMusic): return appleMusic
        case .system, .dedicated(.otherApps), .none: return system
        }
    }

    // MARK: MediaControllerProtocol

    var isWorking: Bool { system?.isWorking ?? true }

    func play() async { await target?.play() }
    func pause() async { await target?.pause() }
    func seek(to time: Double) async { await target?.seek(to: time) }
    func nextTrack() async { await target?.nextTrack() }
    func previousTrack() async { await target?.previousTrack() }
    func togglePlay() async { await target?.togglePlay() }
    func toggleShuffle() async { await target?.toggleShuffle() }
    func toggleRepeat() async { await target?.toggleRepeat() }
    func isActive() -> Bool { target?.isActive() ?? false }

    func updatePlaybackInfo() async {
        await system?.updatePlaybackInfo()
        if spotify.isActive() { await spotify.updatePlaybackInfo() }
        if appleMusic.isActive() { await appleMusic.updatePlaybackInfo() }
    }

    @MainActor var canEverFavorite: Bool { target?.canEverFavorite ?? false }
    @MainActor var supportsFavoriting: Bool { target?.supportsFavoriting ?? false }
    @MainActor var favoritingIsReadOnly: Bool { target?.favoritingIsReadOnly ?? false }
    func isCurrentTrackFavorited() async -> Bool? { await target?.isCurrentTrackFavorited() }
    @discardableResult
    func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        await target?.setCurrentTrackFavorited(favorited) ?? false
    }
}
