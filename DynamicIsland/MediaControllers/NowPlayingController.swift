/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import AppKit
import Combine
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    // Stub for now to conform with ControllerProtocol
    func updatePlaybackInfo() async {}

    /// How recent a sender's timestamp has to be for the position beside it to
    /// count as a reading of now rather than a record of something earlier.
    ///
    /// Generous on purpose: it only has to separate a sample taken this moment
    /// from one a sender has been repeating since it paused, and those are
    /// minutes apart, not seconds.
    private static let currentSampleWindow: TimeInterval = 2

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }
    
    /// Whether the system Now Playing can be read here: false only when the
    /// adapter could not be launched. The adapter itself is not running all
    /// the time (see `AdapterDemand`), so its process says nothing about it.
    var isWorking: Bool {
        !adapterLaunchFailed
    }
    private var lastMusicItem:
        (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    /// What the system reports, merged from the adapter's diffs. What is
    /// shown is `playbackState`, which leaves a video without track details out.
    private var rawState: PlaybackState = .init(bundleIdentifier: "com.apple.Music")
    private var hold = MusicOnlyHold()
    private var settleTask: Task<Void, Never>?

    /// Whether a video holds the system's controls while the music stays on
    /// screen. Every command would reach the video then, so none is sent.
    private var controlsAreHeld: Bool { playbackState.controlsTakenBy != nil }

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?

    // MARK: - Adapter demand

    /// When the adapter (a perl process) runs: from the moment another app
    /// starts sending audio until, for `idleGrace`, no app sends any and the
    /// adapter reports nothing playing; never while the Mac or its screen
    /// sleeps. Upstream started it at launch and kept it for the whole
    /// session.
    enum AdapterDemand {
        /// Longer than the island keeps a paused track (`waitInterval`, 10 s).
        static let idleGrace: TimeInterval = 30
        static let firstRestartDelay: TimeInterval = 2
        static let maximumRestartDelay: TimeInterval = 60

        /// Whether a report keeps the adapter from going idle.
        static func reportCountsAsPlaying(isPlaying: Bool, title: String) -> Bool {
            isPlaying && !title.isEmpty
        }

        static func nextRestartDelay(after delay: TimeInterval) -> TimeInterval {
            min(max(delay, firstRestartDelay) * 2, maximumRestartDelay)
        }
    }

    private let outputActivity = AudioOutputActivity()
    private var screenInUse = true
    private var gateCancellable: AnyCancellable?
    private var idleStopWork: DispatchWorkItem?
    private var restartWork: DispatchWorkItem?
    private var restartDelay = AdapterDemand.firstRestartDelay
    private var adapterLaunchFailed = false
    /// Set while the adapter is being started (its launch is asynchronous).
    private var adapterStarting = false
    /// What the last report said, read on the main thread.
    private var lastReportPlaying = false

    var isAdapterRunning: Bool { process?.isRunning == true || adapterStarting }

    // MARK: - Initialization
    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)
            
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        DispatchQueue.main.async { [weak self] in self?.beginWatchingForPlayers() }
    }

    /// Follows the gate and audio output; the adapter starts from there.
    private func beginWatchingForPlayers() {
        outputActivity.onOutputStarted = { [weak self] in self?.startAdapterIfNeeded() }
        outputActivity.onActivityChanged = { [weak self] outputting in
            guard let self, self.process != nil else { return }
            if outputting {
                self.idleStopWork?.cancel()
                self.idleStopWork = nil
            } else if !self.lastReportPlaying, self.idleStopWork == nil {
                self.scheduleIdleStop()
            }
        }
        gateCancellable = ActivityGate.shared.publisher(for: .screenInUse)
            .sink { [weak self] inUse in
                guard let self else { return }
                self.screenInUse = inUse
                if inUse {
                    // Back (wake, display on): music still playing starts it.
                    self.outputActivity.start()
                } else {
                    self.outputActivity.stop()
                    self.stopAdapter()
                    self.freezePlaybackState()
                }
            }
    }

    /// With the adapter gone nothing would ever report the music stopping, and
    /// a "playing" left behind keeps the visualizer and the progress moving.
    /// Shown as paused where it got to; a player still going when the screen
    /// is back starts the adapter again, and its report replaces this.
    private func freezePlaybackState() {
        guard rawState.isPlaying else { return }
        let now = Date()
        var frozen = rawState
        frozen.currentTime = max(0, rawState.currentTime + now.timeIntervalSince(rawState.lastUpdated) * rawState.playbackRate)
        frozen.lastUpdated = now
        frozen.isPlaying = false
        rawState = frozen
        lastReportPlaying = false
        publish(now: now)
    }

    private func startAdapterIfNeeded() {
        guard screenInUse, !isAdapterRunning, !adapterLaunchFailed else { return }
        restartWork?.cancel()
        restartWork = nil
        adapterStarting = true
        lastReportPlaying = false
        // Nothing reported yet: if nothing plays, it stops again after the grace.
        scheduleIdleStop()
        Task { [weak self] in
            await self?.setupNowPlayingObserver()
        }
    }

    /// Stops the adapter process; the island keeps the last report.
    private func stopAdapter() {
        idleStopWork?.cancel()
        idleStopWork = nil
        restartWork?.cancel()
        restartWork = nil
        restartDelay = AdapterDemand.firstRestartDelay
        guard let process else { return }
        process.terminationHandler = nil
        if process.isRunning {
            // Its end of the pipe closes with it, which ends the stream task.
            process.terminate()
        }
        self.process = nil
        // Not closed here: the read that is waiting would never be answered.
        // The pipe ends with the process, which ends the read, the stream
        // task and with it the last hold on the pipe.
        pipeHandler = nil
        streamTask = nil
    }

    private func scheduleIdleStop() {
        idleStopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.idleStopWork = nil
            // A player that keeps its output open while paused resumes
            // without a new start of output, so sound keeps it too.
            guard !self.lastReportPlaying, !self.outputActivity.anyOtherOutput else { return }
            self.stopAdapter()
        }
        idleStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AdapterDemand.idleGrace, execute: work)
    }

    /// Every report: playing keeps the adapter, anything else starts the grace.
    private func noteAdapterReport(playing: Bool) {
        lastReportPlaying = playing
        if playing {
            idleStopWork?.cancel()
            idleStopWork = nil
            restartDelay = AdapterDemand.firstRestartDelay
        } else if idleStopWork == nil, process != nil, !outputActivity.anyOtherOutput {
            scheduleIdleStop()
        }
    }

    /// The adapter exited without being asked: back after a growing pause
    /// while something plays (2 s, doubling to a minute), not in a loop.
    private func adapterExitedOnItsOwn() {
        process = nil
        pipeHandler = nil
        streamTask = nil
        idleStopWork?.cancel()
        idleStopWork = nil
        guard screenInUse, outputActivity.anyOtherOutput else {
            freezePlaybackState()
            return
        }
        let delay = restartDelay
        restartDelay = AdapterDemand.nextRestartDelay(after: restartDelay)
        let work = DispatchWorkItem { [weak self] in
            self?.restartWork = nil
            self?.startAdapterIfNeeded()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    deinit {
        streamTask?.cancel()
        settleTask?.cancel()
        
        if let pipeHandler = self.pipeHandler {
            Task { await pipeHandler.close()
            }
        }
        
        if let process = self.process {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        self.process = nil
        self.pipeHandler = nil
    }

    // MARK: - Protocol Implementation
    func play() async {
        guard !controlsAreHeld else { return }
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        guard !controlsAreHeld else { return }
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        guard !controlsAreHeld else { return }
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        guard !controlsAreHeld else { return }
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() async {
        guard !controlsAreHeld else { return }
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        guard !controlsAreHeld else { return }
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        return true
    }

    // MARK: - Favouriting

    /// This source fronts whatever app is playing, so favouriting has to be
    /// answered by that app rather than by the source. Under Now Playing the
    /// user has not told us which player they are using -- MediaRemote has.
    @MainActor
    var canEverFavorite: Bool {
        switch playbackState.bundleIdentifier {
        case AppleMusicFavoriting.bundleIdentifier,
             SpotifyController.bundleIdentifier,
             YouTubeMusicFavoriting.bundleIdentifier,
             TidalAccessibility.bundleIdentifier:
            return true
        default:
            return false
        }
    }

    @MainActor
    var supportsFavoriting: Bool {
        switch playbackState.bundleIdentifier {
        case AppleMusicFavoriting.bundleIdentifier:
            return AppleMusicFavoriting.isAvailable
        case SpotifyController.bundleIdentifier:
            return SpotifyFavoriting.isAvailable
        case YouTubeMusicFavoriting.bundleIdentifier:
            return YouTubeMusicFavoriting.default.isAvailable
        case TidalAccessibility.bundleIdentifier:
            return TidalAccessibility.isAvailable
        default:
            return false
        }
    }

    /// TIDAL reports the favourited state but will not accept a change.
    @MainActor
    var favoritingIsReadOnly: Bool {
        playbackState.bundleIdentifier == TidalAccessibility.bundleIdentifier
    }

    func isCurrentTrackFavorited() async -> Bool? {
        switch playbackState.bundleIdentifier {
        case AppleMusicFavoriting.bundleIdentifier:
            return await AppleMusicFavoriting.isCurrentTrackFavorited()
        case SpotifyController.bundleIdentifier:
            return await SpotifyFavoriting.isFavorited(
                contentIdentifier: playbackState.contentIdentifier,
                contentURL: playbackState.contentURL
            )
        case YouTubeMusicFavoriting.bundleIdentifier:
            return await YouTubeMusicFavoriting.default.isCurrentTrackFavorited()
        case TidalAccessibility.bundleIdentifier:
            return await TidalAccessibility.isCurrentTrackFavorited()
        default:
            return nil
        }
    }

    @discardableResult
    func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        switch playbackState.bundleIdentifier {
        case AppleMusicFavoriting.bundleIdentifier:
            return await AppleMusicFavoriting.setCurrentTrackFavorited(favorited)
        case SpotifyController.bundleIdentifier:
            return await SpotifyFavoriting.setFavorited(
                favorited,
                contentIdentifier: playbackState.contentIdentifier,
                contentURL: playbackState.contentURL
            )
        case YouTubeMusicFavoriting.bundleIdentifier:
            return await YouTubeMusicFavoriting.default.setCurrentTrackFavorited(favorited)
        default:
            return false
        }
    }
    
    func toggleShuffle() async {
        guard !controlsAreHeld else { return }
        // TIDAL never registered a shuffle command, so the Media Remote call
        // below reaches nothing: the button moved and the app carried on. Its
        // Playback menu is the one place that both reports and accepts it.
        if playbackState.bundleIdentifier == TidalAccessibility.bundleIdentifier {
            let current = await TidalAccessibility.isShuffled() ?? playbackState.isShuffled
            guard await TidalAccessibility.setShuffled(!current) else { return }
            await MainActor.run {
                rawState.isShuffled = !current
                playbackState.isShuffled = !current
            }
            return
        }

        // MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
        rawState.isShuffled = playbackState.isShuffled
    }
    
    func toggleRepeat() async {
        guard !controlsAreHeld else { return }
        // Same as shuffle, and the menu is better than a cycling button: each
        // repeat item sets its own mode, so there is nothing to overshoot.
        if playbackState.bundleIdentifier == TidalAccessibility.bundleIdentifier {
            let current = await TidalAccessibility.repeatMode() ?? playbackState.repeatMode
            let next: RepeatMode
            switch current {
            case .off: next = .all
            case .all: next = .one
            case .one: next = .off
            }
            guard await TidalAccessibility.setRepeatMode(next) else { return }
            await MainActor.run {
                rawState.repeatMode = next
                playbackState.repeatMode = next
            }
            return
        }

        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        rawState.repeatMode = playbackState.repeatMode
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            //let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
            let frameworkPath =
                Bundle.main.resourceURL?
                    .appendingPathComponent("MediaRemoteAdapter.framework")
                    .path

        else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            await MainActor.run {
                self.adapterStarting = false
                self.adapterLaunchFailed = true
            }
            return
        }

        let pipeHandler = JSONLinesPipeHandler()
        let outputPipe = await pipeHandler.getPipe()
        await MainActor.run {
            self.launchAdapter(script: scriptURL, framework: frameworkPath, output: outputPipe, pipeHandler: pipeHandler)
        }
    }

    /// On the main thread, like `stopAdapter`, so a stop never races a start.
    private func launchAdapter(script scriptURL: URL, framework frameworkPath: String,
                               output outputPipe: Pipe, pipeHandler: JSONLinesPipeHandler) {
        adapterStarting = false
        // The screen went to sleep, or another start won, while this one was
        // on its way.
        guard screenInUse, process == nil else {
            Task { await pipeHandler.close() }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // --micros swaps the time keys for microsecond equivalents. The default
        // "timestamp" is an ISO-8601 string truncated to whole seconds, which
        // throws away up to a second of the playback anchor and makes every
        // position estimate drift by that much.
        process.arguments = [scriptURL.path, frameworkPath, "stream", "--micros"]
        process.standardOutput = outputPipe

        // Capture stderr so framework/script errors are logged
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // End of file: left installed, the handler is called again at
                // once, for ever (a core at 100% once the adapter exits).
                handle.readabilityHandler = nil
                return
            }
            guard let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty
            else { return }
            print("NowPlayingController [stderr]: \(message)")
        }

        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.async {
                guard let self, let process, self.process === process else { return }
                self.adapterExitedOnItsOwn()
            }
        }

        do {
            try process.run()
        } catch {
            adapterLaunchFailed = true
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            Task { await pipeHandler.close() }
            print("NowPlayingController: failed to launch mediaremote-adapter.pl: \(error)")
            return
        }

        self.process = process
        self.pipeHandler = pipeHandler
        // Only the handler and a weak self: upstream's task held the
        // controller for as long as the stream ran, so a replaced controller
        // and its perl process were never freed.
        // The task itself captures self weakly too: without it the inner
        // [weak self] makes the task hold self strongly (#ImplicitStrongCapture).
        streamTask = Task { [weak self] in
            await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
                await self?.handleAdapterUpdate(update)
            }
        }
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: rawState.bundleIdentifier)
        
        newPlaybackState.title = payload.title ?? (diff ? self.rawState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.rawState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.rawState.album : "")
        newPlaybackState.duration = payload.resolvedDuration ?? (diff ? self.rawState.duration : 0)

        // The reported position and the instant it was sampled are a matched pair:
        // elapsedTime is the position *at* timestamp. They have to be adopted or
        // carried forward together -- pairing a fresh position with the previous
        // update's anchor makes every estimate run ahead by the age of that anchor.
        if let elapsed = payload.resolvedElapsedTime {
            newPlaybackState.currentTime = elapsed
            newPlaybackState.lastUpdated = payload.resolvedTimestamp ?? Date()
        } else if payload.clearsElapsedTime {
            // The sender named the position and set it to null, so there is
            // nothing left to extrapolate from. Carrying the old pair forward
            // here would keep advancing a position the sender has disowned.
            newPlaybackState.currentTime = 0
            newPlaybackState.lastUpdated = payload.resolvedTimestamp ?? Date()
        } else if diff {
            newPlaybackState.currentTime = self.rawState.currentTime
            newPlaybackState.lastUpdated = self.rawState.lastUpdated
        } else {
            newPlaybackState.currentTime = 0
            newPlaybackState.lastUpdated = payload.resolvedTimestamp ?? Date()
        }

        // Senders are not obliged to keep publishing. Spotify anchors once when
        // a track starts and then says nothing for the rest of it -- measured
        // here as an elapsed of 0 paired with a timestamp 141 seconds old, on a
        // track that had been playing for exactly that long. Extrapolating from
        // a stale anchor is fine while the music is running, because wall-clock
        // time and playback time advance together.
        //
        // They stop agreeing the moment playback stops. A pause that the sender
        // does not follow with a fresh position leaves the anchor where it was,
        // so when playback resumes the extrapolation silently counts the paused
        // time as played, and every pause pushes the estimate further ahead --
        // which is why the position could only be brought back by pausing and
        // playing until the sender happened to republish.
        //
        // So the position is re-anchored on the transition itself: frozen where
        // it had got to when playback stops, and restarted from there when it
        // resumes.
        let wasPlaying = self.rawState.isPlaying
        let isPlayingNow = payload.playing ?? (diff ? wasPlaying : false)

        // Whether the sender sent a position is not the question -- whether it
        // sent a *current* one is. Spotify keeps republishing the exact instant
        // it paused: four reads six seconds apart returned the same 40.342 with
        // its timestamp 235, 241, 247 and 254 seconds old, still climbing. That
        // pair is true, and harmless while paused because nothing extrapolates
        // a stopped track. It becomes wrong the moment playback resumes, when
        // the anchor still points to before the pause and the whole stopped
        // interval gets counted as played.
        let now = Date()
        let hasCurrentSample: Bool = {
            guard payload.resolvedElapsedTime != nil else { return false }
            // No timestamp means it was stamped on arrival, so it is current
            // by construction.
            guard let stamp = payload.resolvedTimestamp else { return true }
            return abs(now.timeIntervalSince(stamp)) <= Self.currentSampleWindow
        }()

        if wasPlaying != isPlayingNow, !hasCurrentSample {
            // The transition is being observed now, so now is when it happened.
            // The payload's own timestamp is only better than that if it is
            // about now as well -- and the stale one is what caused this.
            let transitionInstant: Date = {
                guard let stamp = payload.resolvedTimestamp,
                      abs(now.timeIntervalSince(stamp)) <= Self.currentSampleWindow
                else { return now }
                return stamp
            }()

            if wasPlaying {
                let elapsedWhilePlaying = transitionInstant.timeIntervalSince(self.rawState.lastUpdated)
                newPlaybackState.currentTime = max(
                    0,
                    self.rawState.currentTime + (elapsedWhilePlaying * self.rawState.playbackRate)
                )
            } else {
                // Resuming. The position is wherever it was left, and the
                // frozen one is what this controller worked out when the pause
                // was observed -- the payload's is the sample already known to
                // be stale, which for some senders is a repeated zero that
                // would restart the track. A seek while paused publishes a
                // fresh sample, so it never reaches this branch.
                newPlaybackState.currentTime = max(0, self.rawState.currentTime)
            }

            newPlaybackState.lastUpdated = transitionInstant
        }

        
        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if !diff {
            newPlaybackState.isShuffled = false
        } else {
            newPlaybackState.isShuffled = self.rawState.isShuffled
        }
        if let repeatModeValue = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if !diff {
            newPlaybackState.repeatMode = .off
        } else {
            newPlaybackState.repeatMode = self.rawState.repeatMode
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if !diff {
            newPlaybackState.artwork = nil
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.rawState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.rawState.isPlaying : false)
        newPlaybackState.bundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.rawState.bundleIdentifier : "")
        )
        
        self.rawState = newPlaybackState
        publish(now: now)
        let playing = AdapterDemand.reportCountsAsPlaying(isPlaying: newPlaybackState.isPlaying, title: newPlaybackState.title)
        await MainActor.run { self.noteAdapterReport(playing: playing) }
    }

    /// Publishes what the system reports, minus a video without track details
    /// (see `MusicOnlyHold`).
    private func publish(now: Date) {
        settleTask?.cancel()
        settleTask = nil
        playbackState = hold.admit(rawState, now: now)
        guard let deadline = hold.settleDeadline else { return }
        // Nothing more may arrive, so the report is looked at again once it
        // has had its time.
        let delay = max(0, deadline.timeIntervalSince(Date()))
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.publish(now: Date())
        }
    }
}

struct NowPlayingUpdate: Codable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    /// Microsecond variants, emitted in place of the keys above when the adapter
    /// runs with --micros. Preferred because the plain "timestamp" is truncated
    /// to whole seconds.
    let durationMicros: Double?
    let elapsedTimeMicros: Double?
    let timestampEpochMicros: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?

    /// Whether the update names a position field and sets it to null.
    ///
    /// A diff omits what has not changed, so an absent position means "carry the
    /// last one forward". A position that is present but null is the sender
    /// saying it no longer has one. Optional decoding renders both as nil, so
    /// the distinction has to be captured while the container is still in hand
    /// -- otherwise a cleared position is mistaken for an unchanged one and the
    /// old position keeps being extrapolated from.
    let clearsElapsedTime: Bool

    private enum CodingKeys: String, CodingKey {
        case title, artist, album, duration, elapsedTime
        case durationMicros, elapsedTimeMicros, timestampEpochMicros
        case shuffleMode, repeatMode, artworkData, timestamp
        case playbackRate, playing
        case parentApplicationBundleIdentifier, bundleIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        title = try container.decodeIfPresent(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        elapsedTime = try container.decodeIfPresent(Double.self, forKey: .elapsedTime)
        durationMicros = try container.decodeIfPresent(Double.self, forKey: .durationMicros)
        elapsedTimeMicros = try container.decodeIfPresent(Double.self, forKey: .elapsedTimeMicros)
        timestampEpochMicros = try container.decodeIfPresent(Double.self, forKey: .timestampEpochMicros)
        shuffleMode = try container.decodeIfPresent(Int.self, forKey: .shuffleMode)
        repeatMode = try container.decodeIfPresent(Int.self, forKey: .repeatMode)
        artworkData = try container.decodeIfPresent(String.self, forKey: .artworkData)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate)
        playing = try container.decodeIfPresent(Bool.self, forKey: .playing)
        parentApplicationBundleIdentifier = try container.decodeIfPresent(
            String.self, forKey: .parentApplicationBundleIdentifier
        )
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)

        func isExplicitlyNull(_ key: CodingKeys) throws -> Bool {
            try container.contains(key) && container.decodeNil(forKey: key)
        }

        clearsElapsedTime = try isExplicitlyNull(.elapsedTime)
            || isExplicitlyNull(.elapsedTimeMicros)
    }
}

extension NowPlayingPayload {
    private static let isoFormatter = ISO8601DateFormatter()

    var resolvedDuration: Double? {
        if let durationMicros { return durationMicros / 1_000_000 }
        return duration
    }

    var resolvedElapsedTime: Double? {
        if let elapsedTimeMicros { return elapsedTimeMicros / 1_000_000 }
        return elapsedTime
    }

    /// The instant ``resolvedElapsedTime`` was sampled.
    ///
    /// Prefers the microsecond epoch value. The ISO-8601 string is only a
    /// fallback for adapters that do not honour --micros: it is formatted as
    /// `yyyy-MM-dd'T'HH:mm:ss'Z'`, so it silently drops the sub-second part of
    /// the anchor and biases the position estimate forward by up to a second.
    var resolvedTimestamp: Date? {
        if let timestampEpochMicros {
            return Date(timeIntervalSince1970: timestampEpochMicros / 1_000_000)
        }
        guard let timestamp else { return nil }
        return Self.isoFormatter.date(from: timestamp)
    }
}

actor JSONLinesPipeHandler {
    private let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""
    
    init() {
        self.pipe = Pipe()
        self.fileHandle = pipe.fileHandleForReading
    }
    
    func getPipe() -> Pipe {
        return pipe
    }
    
    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        do {
            try await self.processLines(as: type) { decodedObject in
                await onLine(decodedObject)
            }
        } catch {
            print("Error processing JSON stream: \(error)")
        }
    }
    
    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }
            
            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)
                
                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])
                    
                    if !line.isEmpty {
                        await processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }
    
    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) async -> Void) async {
        guard let data = line.data(using: .utf8) else {
            return
        }
        do {
            let decodedObject = try JSONDecoder().decode(T.self, from: data)
            await onLine(decodedObject)
        } catch {
            // Ignore lines that can't be decoded
        }
    }
    
    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }
    
    func close() async {
        do {
            fileHandle.readabilityHandler = nil
            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            print("Error closing pipe handler: \(error)")
        }
    }
}
