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

    func play() async { await target?.play(); askAboutPlayerAfterClick() }
    func pause() async { await target?.pause(); askAboutPlayerAfterClick() }
    func seek(to time: Double) async { await target?.seek(to: time); askAboutPlayerAfterClick() }
    func nextTrack() async { await target?.nextTrack(); askAboutPlayerAfterClick() }
    func previousTrack() async { await target?.previousTrack(); askAboutPlayerAfterClick() }
    func togglePlay() async { await target?.togglePlay(); askAboutPlayerAfterClick() }
    func toggleShuffle() async { await target?.toggleShuffle(); askAboutPlayerAfterClick() }
    func toggleRepeat() async { await target?.toggleRepeat(); askAboutPlayerAfterClick() }
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
        let done = await target?.setCurrentTrackFavorited(favorited) ?? false
        askAboutPlayerAfterClick()
        return done
    }

    // MARK: Automation (§5.8)

    /// Auto sends Music and Spotify no Apple Event until macOS allows it or a
    /// player control is clicked; until then it shows them through the system
    /// Now Playing, whose controls send them nothing either. So after such a
    /// click the player it was about reads itself once, through the check that
    /// may ask. After a yes its own reports take over and Auto ranks it, the
    /// canvas and the heart included, as on a Mac that allowed it long ago
    /// (there `refreshAfterClick` returns at once). Media keys and the
    /// play/pause shortcut count as clicks, as they do everywhere.
    private func askAboutPlayerAfterClick() {
        let source = Self.playerToAskAbout(
            choice: choice,
            systemApp: systemState?.bundleIdentifier,
            hasSystem: system != nil,
            order: Defaults[.autoMediaSourceOrder],
            ignored: Set(Defaults[.autoMediaIgnoredApps]),
            isRunning: { [spotify, appleMusic] source in
                source == .spotify ? spotify.isActive() : appleMusic.isActive()
            }
        )
        switch source {
        case .spotify: Task { [spotify] in await spotify.refreshAfterClick() }
        case .appleMusic: Task { [appleMusic] in await appleMusic.refreshAfterClick() }
        case .otherApps, nil: break
        }
    }

    /// The player a click is about while Auto shows no dedicated one: Spotify
    /// or Music while macOS reports it, or, where the system Now Playing does
    /// not work (MediaChecker) and nothing is shown, the first of them in the
    /// user's order that runs and is not ignored. A dedicated choice is
    /// already allowed, and anything else is not Spotify or Music: nil.
    static func playerToAskAbout(
        choice: AutoSourceChoice,
        systemApp: String?,
        hasSystem: Bool,
        order: [AutoMediaSource],
        ignored: Set<String>,
        isRunning: (AutoMediaSource) -> Bool
    ) -> AutoMediaSource? {
        switch choice {
        case .system:
            let source = systemApp.map(AutoMediaSource.source(for:)) ?? .otherApps
            return source == .otherApps ? nil : source
        case .none where !hasSystem:
            return AutoSourceResolver.normalizedOrder(order).first { source in
                guard let bundleID = source.bundleIdentifier, !ignored.contains(bundleID) else { return false }
                return isRunning(source)
            }
        case .none, .dedicated:
            return nil
        }
    }
}
