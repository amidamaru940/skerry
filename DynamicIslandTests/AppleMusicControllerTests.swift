/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Combine
import os
import XCTest
@testable import Atoll

@MainActor
final class AppleMusicControllerTests: XCTestCase {
    private actor EventRecorder {
        private var events: [String] = []

        func record(_ event: String) {
            events.append(event)
        }

        func snapshot() -> [String] {
            events
        }
    }

    private actor PlaybackInfoProvider {
        private var values: [AppleMusicPlaybackInfo]

        init(values: [AppleMusicPlaybackInfo]) {
            self.values = values
        }

        func next() -> AppleMusicPlaybackInfo? {
            values.isEmpty ? nil : values.removeFirst()
        }
    }

    private actor OutOfOrderPlaybackInfoProvider {
        private var nextRequestID = 0
        private var continuations: [Int: CheckedContinuation<AppleMusicPlaybackInfo?, Never>] = [:]

        func next() async -> AppleMusicPlaybackInfo? {
            let requestID = nextRequestID
            nextRequestID += 1
            return await withCheckedContinuation { continuation in
                continuations[requestID] = continuation
            }
        }

        func waitForRequestCount(_ count: Int) async {
            while continuations.count < count {
                await Task.yield()
            }
        }

        func complete(requestID: Int, with info: AppleMusicPlaybackInfo?) {
            continuations.removeValue(forKey: requestID)?.resume(returning: info)
        }
    }

    private actor DeferredArtworkProvider {
        private var continuation: CheckedContinuation<Data?, Never>?
        private var completedArtwork: Data?
        private var isCompleted = false

        func fetch(title: String, artist: String, album: String) async -> Data? {
            if isCompleted {
                return completedArtwork
            }

            precondition(
                continuation == nil,
                "DeferredArtworkProvider supports one pending fetch"
            )
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func waitUntilRequested(timeout: Duration) async -> Bool {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)

            while continuation == nil {
                guard clock.now < deadline else { return false }
                await Task.yield()
            }
            return true
        }

        func complete(with artwork: Data?) {
            isCompleted = true
            completedArtwork = artwork
            continuation?.resume(returning: artwork)
            continuation = nil
        }
    }

    func testCatalogSearchURLSafelyEncodesQueryItems() {
        let query = "Rock & Roll = Live + Remix?"
        let url = makeAppleMusicCatalogSearchURL(query: query)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let queryItems = Dictionary<String, String?>(
            uniqueKeysWithValues: components?.queryItems?.map { ($0.name, $0.value) } ?? []
        )

        XCTAssertEqual(queryItems["term"], query)
        XCTAssertEqual(queryItems["media"], "music")
        XCTAssertEqual(queryItems["entity"], "song")
        XCTAssertEqual(queryItems["limit"], "10")
    }

    func testDeferredArtworkProviderWaitTimesOutWithoutRequest() async {
        let provider = DeferredArtworkProvider()

        let wasRequested = await provider.waitUntilRequested(timeout: .milliseconds(10))

        XCTAssertFalse(wasRequested)
    }

    func testOptimisticPauseIgnoresStalePlayingEventUntilPausedIsConfirmed() {
        var transition = OptimisticPlaybackTransition()
        transition.begin(expecting: false)

        XCTAssertFalse(transition.shouldApply(eventIsPlaying: true))
        XCTAssertEqual(transition.expectedState, false)
        XCTAssertTrue(transition.shouldApply(eventIsPlaying: false))
        XCTAssertNil(transition.expectedState)
    }

    func testOptimisticResumeIgnoresStalePausedEventUntilPlayingIsConfirmed() {
        var transition = OptimisticPlaybackTransition()
        transition.begin(expecting: true)

        XCTAssertFalse(transition.shouldApply(eventIsPlaying: false))
        XCTAssertEqual(transition.expectedState, true)
        XCTAssertTrue(transition.shouldApply(eventIsPlaying: true))
        XCTAssertNil(transition.expectedState)
    }

    func testManualTrackArtworkHandoffDelaysPosterBy225Milliseconds() async {
        let manager = MusicManager(startsControllerSetup: false)
        let newArtwork = NSImage(size: NSSize(width: 48, height: 48))
        let artworkPublished = expectation(description: "delayed artwork published")
        let startedAt = Date()
        var observedDelay: TimeInterval = 0
        let cancellable = manager.$albumArt.sink { artwork in
            guard artwork === newArtwork else { return }
            observedDelay = Date().timeIntervalSince(startedAt)
            artworkPublished.fulfill()
        }
        defer { manager.destroy() }

        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: newArtwork)

        XCTAssertFalse(manager.albumArt === newArtwork)
        await fulfillment(of: [artworkPublished], timeout: 1)
        XCTAssertGreaterThanOrEqual(observedDelay, 0.20)
        withExtendedLifetime(cancellable) {}
    }

    func testRepeatedManualTrackHandoffPreservesPendingPosterWhenArtworkDoesNotChange() async {
        let manager = MusicManager(startsControllerSetup: false)
        let sharedArtwork = NSImage(size: NSSize(width: 48, height: 48))
        let artworkPublished = expectation(description: "pending shared artwork published")
        let cancellable = manager.$albumArt.sink { artwork in
            guard artwork === sharedArtwork else { return }
            artworkPublished.fulfill()
        }
        defer { manager.destroy() }

        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: sharedArtwork)
        manager.beginManualTrackArtworkHandoff()

        await fulfillment(of: [artworkPublished], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }

    func testRepeatedManualTrackHandoffPublishesOnlyNewestPoster() async {
        let manager = MusicManager(startsControllerSetup: false)
        let firstArtwork = NSImage(size: NSSize(width: 48, height: 48))
        let newestArtwork = NSImage(size: NSSize(width: 64, height: 64))
        let newestArtworkPublished = expectation(description: "newest artwork published")
        var firstArtworkWasPublished = false
        let cancellable = manager.$albumArt.sink { artwork in
            if artwork === firstArtwork {
                firstArtworkWasPublished = true
            } else if artwork === newestArtwork {
                newestArtworkPublished.fulfill()
            }
        }
        defer { manager.destroy() }

        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: firstArtwork)
        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: newestArtwork)

        await fulfillment(of: [newestArtworkPublished], timeout: 1)
        XCTAssertFalse(firstArtworkWasPublished)
        withExtendedLifetime(cancellable) {}
    }

    func testAutomaticTrackArtworkUpdateAppliesImmediatelyWithoutManualHandoff() {
        let manager = MusicManager(startsControllerSetup: false)
        let oldArtwork = NSImage(size: NSSize(width: 24, height: 24))
        let newArtwork = NSImage(size: NSSize(width: 32, height: 32))
        defer { manager.destroy() }

        manager.updateAlbumArt(newAlbumArt: oldArtwork)
        manager.updateAlbumArt(newAlbumArt: newArtwork)

        XCTAssertTrue(manager.albumArt === newArtwork)
    }

    func testNextTrackRefreshesPlaybackInfoWithoutWaitingForNotification() async {
        let recorder = EventRecorder()
        let controller = AppleMusicController(
            commandUpdateDelay: .zero,
            startsObservers: false,
            commandExecutor: { command in
                await recorder.record("command:\(command)")
            },
            playbackInfoProvider: {
                await recorder.record("refresh")
                return nil
            }
        )

        await controller.nextTrack()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["command:next track", "refresh"])
    }

    func testPlaybackStatePublicationReturnsToMainActor() async {
        let statePublished = expectation(description: "playback state published on main actor")
        let controller = AppleMusicController(
            startsObservers: false,
            playbackInfoProvider: {
                AppleMusicPlaybackInfo(
                    isPlaying: true,
                    title: "Main Actor Song",
                    artist: "Main Actor Artist",
                    album: "Main Actor Album",
                    currentTime: 0,
                    duration: 180,
                    isShuffled: false,
                    repeatMode: .off,
                    artwork: Data("artwork".utf8)
                )
            }
        )
        let cancellable = controller.playbackStatePublisher
            .dropFirst()
            .sink { _ in
                XCTAssertTrue(Thread.isMainThread)
                statePublished.fulfill()
            }

        await Task.detached {
            await controller.updatePlaybackInfo()
        }.value

        await fulfillment(of: [statePublished], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }

    func testOlderPlaybackRefreshCannotOverwriteNewerState() async {
        let provider = OutOfOrderPlaybackInfoProvider()
        let controller = AppleMusicController(
            startsObservers: false,
            playbackInfoProvider: { await provider.next() }
        )
        var publishedTitles: [String] = []
        let cancellable = controller.playbackStatePublisher
            .dropFirst()
            .sink { publishedTitles.append($0.title) }
        let oldInfo = AppleMusicPlaybackInfo(
            isPlaying: true,
            title: "Old Song",
            artist: "Old Artist",
            album: "Old Album",
            currentTime: 10,
            duration: 180,
            isShuffled: false,
            repeatMode: .off,
            artwork: Data("old-artwork".utf8)
        )
        let newInfo = AppleMusicPlaybackInfo(
            isPlaying: true,
            title: "New Song",
            artist: "New Artist",
            album: "New Album",
            currentTime: 0,
            duration: 180,
            isShuffled: false,
            repeatMode: .off,
            artwork: Data("new-artwork".utf8)
        )

        let olderRefresh = Task { await controller.updatePlaybackInfo() }
        await provider.waitForRequestCount(1)
        let newerRefresh = Task { await controller.updatePlaybackInfo() }
        await provider.waitForRequestCount(2)

        await provider.complete(requestID: 1, with: newInfo)
        await newerRefresh.value
        await provider.complete(requestID: 0, with: oldInfo)
        await olderRefresh.value

        XCTAssertEqual(publishedTitles, ["New Song"])
        withExtendedLifetime(cancellable) {}
    }

    func testControllerDeallocatesWhileArtworkProviderIsUnresolved() async {
        let deferredArtwork = DeferredArtworkProvider()
        var controller: AppleMusicController? = AppleMusicController(
            startsObservers: false,
            playbackInfoProvider: {
                AppleMusicPlaybackInfo(
                    isPlaying: true,
                    title: "Pending Artwork Song",
                    artist: "Pending Artwork Artist",
                    album: "Pending Artwork Album",
                    currentTime: 0,
                    duration: 180,
                    isShuffled: false,
                    repeatMode: .off,
                    artwork: nil
                )
            },
            catalogArtworkProvider: { title, artist, album in
                await deferredArtwork.fetch(title: title, artist: artist, album: album)
            }
        )
        weak var weakController = controller

        await controller?.updatePlaybackInfo()
        let artworkWasRequested = await deferredArtwork.waitUntilRequested(timeout: .seconds(1))
        XCTAssertTrue(artworkWasRequested)
        controller = nil

        XCTAssertNil(weakController)
        await deferredArtwork.complete(with: nil)
    }

    func testPublishesNewTrackBeforeCatalogArtworkFinishes() async {
        let oldArtwork = Data("old-artwork".utf8)
        let newArtwork = Data("new-artwork".utf8)
        let deferredArtwork = DeferredArtworkProvider()
        let artworkPublished = expectation(description: "new artwork published")
        let playbackInfoProvider = PlaybackInfoProvider(values: [
            AppleMusicPlaybackInfo(
                isPlaying: true,
                title: "Old Song",
                artist: "Old Artist",
                album: "Old Album",
                currentTime: 30,
                duration: 180,
                isShuffled: false,
                repeatMode: .off,
                artwork: oldArtwork
            ),
            AppleMusicPlaybackInfo(
                isPlaying: true,
                title: "New Song",
                artist: "New Artist",
                album: "New Album",
                currentTime: 0,
                duration: 180,
                isShuffled: false,
                repeatMode: .off,
                artwork: nil
            )
        ])
        let controller = AppleMusicController(
            startsObservers: false,
            playbackInfoProvider: { await playbackInfoProvider.next() },
            catalogArtworkProvider: { title, artist, album in
                await deferredArtwork.fetch(title: title, artist: artist, album: album)
            }
        )
        var states: [PlaybackState] = []
        let cancellable = controller.playbackStatePublisher.sink { state in
            states.append(state)
            if state.artwork == newArtwork {
                artworkPublished.fulfill()
            }
        }

        await controller.updatePlaybackInfo()
        XCTAssertEqual(states.last?.artwork, oldArtwork)

        await controller.updatePlaybackInfo()

        XCTAssertEqual(states.last?.title, "New Song")
        XCTAssertNil(states.last?.artwork, "The previous song poster must clear before the network fallback completes")

        let artworkWasRequested = await deferredArtwork.waitUntilRequested(timeout: .seconds(1))
        XCTAssertTrue(artworkWasRequested)
        await deferredArtwork.complete(with: newArtwork)
        await fulfillment(of: [artworkPublished], timeout: 1)
        XCTAssertEqual(states.last?.artwork, newArtwork)

        withExtendedLifetime(cancellable) {}
    }
}

/// §5.8: Music and Spotify are scripted only once macOS allows it, and only a
/// click may ask.
final class AutomationConsentTests: XCTestCase {
    /// Whether each look-up asked the person, in order.
    private final class Lookups: @unchecked Sendable {
        private let calls = OSAllocatedUnfairLock(initialState: [Bool]())
        func record(_ askingUser: Bool) { calls.withLock { $0.append(askingUser) } }
        var askingUser: [Bool] { calls.withLock { $0 } }
    }

    /// macOS's answers, one per look-up; the last one stays.
    private final class Answers: @unchecked Sendable {
        private let queue: OSAllocatedUnfairLock<[OSStatus]>
        init(_ answers: [OSStatus]) { queue = OSAllocatedUnfairLock(initialState: answers) }
        func next() -> OSStatus { queue.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] } }
    }

    // noErr, errAEEventWouldRequireUserConsent, errAEEventNotPermitted, procNotFound
    private let allowed: OSStatus = 0
    private let notAsked: OSStatus = -1744
    private let refused: OSStatus = -1743
    private let notRunning: OSStatus = -600

    private func consent(answering result: OSStatus, lookups: Lookups) -> AutomationConsent {
        consent(answering: [result], lookups: lookups)
    }

    private func consent(answering results: [OSStatus], lookups: Lookups) -> AutomationConsent {
        let answers = Answers(results)
        return AutomationConsent(bundleIdentifier: "com.apple.Music", observesApps: false) { _, askingUser in
            lookups.record(askingUser)
            return answers.next()
        }
    }

    func testMacOSAnswersMapToStatuses() {
        XCTAssertEqual(AutomationConsent.Status(allowed), .allowed)
        XCTAssertEqual(AutomationConsent.Status(notAsked), .notAsked)
        XCTAssertEqual(AutomationConsent.Status(refused), .refused)
        XCTAssertEqual(AutomationConsent.Status(notRunning), .notRunning)
        XCTAssertEqual(AutomationConsent.Status(-50), .unknown)
    }

    func testOnlyAYesLetsAnUnclickedEventGo() {
        XCTAssertTrue(AutomationConsent.allowsUnclickedEvent(.allowed))
        for status in [.notAsked, .refused, .notRunning, .unknown] as [AutomationConsent.Status] {
            XCTAssertFalse(AutomationConsent.allowsUnclickedEvent(status), "\(status)")
        }
    }

    func testAClickAsksOnlyWhileMacOSHasNoAnswer() {
        XCTAssertEqual(AutomationConsent.stepForClick(.allowed), .send)
        XCTAssertEqual(AutomationConsent.stepForClick(.notRunning), .send)
        XCTAssertEqual(AutomationConsent.stepForClick(.notAsked), .ask)
        XCTAssertEqual(AutomationConsent.stepForClick(.unknown), .ask)
        XCTAssertEqual(AutomationConsent.stepForClick(.refused), .skip)
    }

    func testAfterAskingOnlyANoHoldsTheEventBack() {
        XCTAssertTrue(AutomationConsent.sendsAfterAsking(.allowed))
        XCTAssertTrue(AutomationConsent.sendsAfterAsking(.notAsked))
        XCTAssertTrue(AutomationConsent.sendsAfterAsking(.notRunning))
        XCTAssertFalse(AutomationConsent.sendsAfterAsking(.refused))
    }

    func testAClosedAppKeepsTheKnownAnswer() {
        XCTAssertEqual(AutomationConsent.merged(.refused, with: .notRunning), .refused)
        XCTAssertEqual(AutomationConsent.merged(.allowed, with: .notRunning), .allowed)
        XCTAssertEqual(AutomationConsent.merged(.notAsked, with: .notRunning), .notAsked)
        XCTAssertEqual(AutomationConsent.merged(.unknown, with: .notRunning), .notRunning)
        XCTAssertEqual(AutomationConsent.merged(.allowed, with: .refused), .refused)
        XCTAssertEqual(AutomationConsent.merged(.refused, with: .allowed), .allowed)
    }

    /// A Mac that already allowed Skerry is scripted as before. A click
    /// reuses the yes without another round trip to macOS.
    func testAClickReusesAYes() async {
        let lookups = Lookups()
        let consent = consent(answering: allowed, lookups: lookups)

        let unclicked = await consent.allowsUnclickedEvent()
        let clicked = await consent.allowsClickedEvent()

        XCTAssertTrue(unclicked && clicked)
        XCTAssertEqual(lookups.askingUser, [false])
        XCTAssertEqual(consent.status, .allowed)
    }

    /// `tccutil reset` while Skerry runs sends no notification: an event
    /// nobody clicked for still looks the answer up, even after a yes, so the
    /// next one does not ask.
    func testAResetIsSeenBeforeTheNextUnclickedEvent() async {
        let lookups = Lookups()
        let consent = consent(answering: [allowed, notAsked], lookups: lookups)

        let before = await consent.allowsUnclickedEvent()
        let after = await consent.allowsUnclickedEvent()

        XCTAssertTrue(before)
        XCTAssertFalse(after)
        XCTAssertEqual(lookups.askingUser, [false, false])
        XCTAssertEqual(consent.status, .notAsked)
    }

    /// A no, then Music quits: the kept answer stays no, but a click goes by
    /// what macOS says now, so the event goes out and launches Music, as it
    /// did before this check (a yes given in System Settings since then works).
    func testAClickOnAClosedAppSendsWhateverWasSaidBefore() async {
        let lookups = Lookups()
        let consent = consent(answering: [refused, notRunning], lookups: lookups)

        let refusedFirst = await consent.refresh()
        let forClick = await consent.lookUpForClick()

        XCTAssertEqual(refusedFirst, .refused)
        XCTAssertEqual(forClick, .notRunning)
        XCTAssertEqual(AutomationConsent.stepForClick(forClick), .send)
        XCTAssertEqual(consent.status, .refused)
        let unclicked = await consent.allowsUnclickedEvent()
        XCTAssertFalse(unclicked)
    }

    /// A fresh install: nothing goes out on its own, and macOS (never the
    /// person) is asked again before every try, so a yes given later counts.
    func testWithoutAnAnswerNothingIsSentAndNobodyIsAsked() async {
        let lookups = Lookups()
        let consent = consent(answering: notAsked, lookups: lookups)

        let first = await consent.allowsUnclickedEvent()
        let second = await consent.allowsUnclickedEvent()

        XCTAssertFalse(first || second)
        XCTAssertEqual(lookups.askingUser, [false, false])
        XCTAssertEqual(consent.status, .notAsked)
    }

    /// To macOS the test host is an app of its own: even a click must not ask.
    func testAClickInTheTestHostNeverAsks() async {
        let lookups = Lookups()
        let consent = consent(answering: notAsked, lookups: lookups)

        let sent = await consent.allowsClickedEvent()

        XCTAssertFalse(sent)
        XCTAssertEqual(lookups.askingUser, [false])
    }

    // MARK: Auto

    private func playerToAskAbout(
        _ choice: AutoSourceChoice,
        systemApp: String? = nil,
        hasSystem: Bool = true,
        order: [AutoMediaSource] = AutoMediaSource.defaultOrder,
        ignored: Set<String> = [],
        running: Set<AutoMediaSource> = []
    ) -> AutoMediaSource? {
        AutoMediaController.playerToAskAbout(
            choice: choice,
            systemApp: systemApp,
            hasSystem: hasSystem,
            order: order,
            ignored: ignored,
            isRunning: { running.contains($0) }
        )
    }

    /// §5.8: in Auto a click on a control shown through the system Now
    /// Playing is about the app macOS reports, when that is Spotify or Music.
    func testAnAutoClickIsAboutTheAppMacOSReports() {
        XCTAssertEqual(playerToAskAbout(.system, systemApp: AutoMediaSource.spotifyBundleID), .spotify)
        XCTAssertEqual(playerToAskAbout(.system, systemApp: AutoMediaSource.appleMusicBundleID), .appleMusic)
        XCTAssertNil(playerToAskAbout(.system, systemApp: "com.apple.Safari"))
        XCTAssertNil(playerToAskAbout(.system, systemApp: nil))
        // A dedicated player is shown only once its app is allowed.
        XCTAssertNil(playerToAskAbout(.dedicated(.spotify)))
        XCTAssertNil(playerToAskAbout(.dedicated(.otherApps)))
        // With the system Now Playing, "nothing playing" is about nobody.
        XCTAssertNil(playerToAskAbout(.none, running: [.spotify, .appleMusic]))
    }

    /// Without the system Now Playing (MediaChecker) Auto shows nothing until
    /// Spotify or Music may be read, so a click is about the first of them,
    /// in the user's order, that runs and is not ignored.
    func testWithoutTheSystemNowPlayingAClickIsAboutARunningPlayer() {
        XCTAssertEqual(playerToAskAbout(.none, hasSystem: false, running: [.appleMusic]), .appleMusic)
        XCTAssertEqual(playerToAskAbout(.none, hasSystem: false, running: [.spotify, .appleMusic]), .spotify)
        XCTAssertEqual(
            playerToAskAbout(.none, hasSystem: false, order: [.otherApps, .appleMusic, .spotify], running: [.spotify, .appleMusic]),
            .appleMusic
        )
        XCTAssertEqual(
            playerToAskAbout(.none, hasSystem: false, ignored: [AutoMediaSource.spotifyBundleID], running: [.spotify, .appleMusic]),
            .appleMusic
        )
        XCTAssertNil(playerToAskAbout(.none, hasSystem: false, running: []))
    }

    /// The read after a click publishes what the player reports, through the
    /// same path as every other read.
    func testTheReadAfterAClickShowsTheTrack() async throws {
        try XCTSkipIf(AutomationConsent.music.status == .allowed, "this host may already script Music")
        let info = AppleMusicPlaybackInfo(isPlaying: true, title: "Asked", artist: "Artist", album: "Album",
                                          currentTime: 0, duration: 60, isShuffled: false, repeatMode: .off,
                                          artwork: Data("art".utf8))
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let controller = AppleMusicController(startsObservers: false, playbackInfoProvider: {
            reads.withLock { $0 += 1 }
            return info
        })
        let shown = expectation(description: "track shown")
        let cancellable = controller.playbackStatePublisher.sink { if $0.title == "Asked" { shown.fulfill() } }

        await controller.refreshAfterClick(launched: true)

        await fulfillment(of: [shown], timeout: 2)
        XCTAssertEqual(reads.withLock { $0 }, 1)
        cancellable.cancel()
    }
}
