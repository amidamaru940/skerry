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

import Combine
import Defaults
import SwiftUI
import AppKit
import AVFoundation

private final class DynamicIslandArtworkLoopRegistry {
    static let shared = DynamicIslandArtworkLoopRegistry()
    private var playersByURL: [URL: DynamicIslandArtworkLoopController] = [:]

    func player(for url: URL) -> DynamicIslandArtworkLoopController {
        if let existing = playersByURL[url] {
            existing.retain()
            return existing
        }
        let controller = DynamicIslandArtworkLoopController(url: url)
        controller.retain()
        playersByURL[url] = controller
        return controller
    }

    func release(_ controller: DynamicIslandArtworkLoopController, for url: URL) {
        controller.release()
        if playersByURL[url] === controller, controller.referenceCount == 0 {
            playersByURL[url] = nil
        }
    }
}

private final class DynamicIslandArtworkLoopController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private var playbackStateCancellable: AnyCancellable?
    var referenceCount = 0

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)

        if MusicManager.shared.isPlaying {
            player.play()
        }

        playbackStateCancellable = MusicManager.shared.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self else { return }
                if isPlaying {
                    self.player.play()
                } else {
                    self.player.pause()
                }
            }
    }

    func retain() {
        referenceCount += 1
    }

    func release() {
        referenceCount -= 1
    }

    deinit {
        player.pause()
        looper = nil
        playbackStateCancellable = nil
    }
}

private final class DynamicIslandArtworkVideoContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        // SwiftUI owns the enclosing transition timing. Prevent the video
        // layer from adding a second implicit frame animation during that
        // transition, which makes Canvas artwork lag behind static artwork.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

private struct DynamicIslandArtworkVideoView: NSViewRepresentable {
    let url: URL
    let videoGravity: AVLayerVideoGravity

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DynamicIslandArtworkVideoContainerView {
        let view = DynamicIslandArtworkVideoContainerView(frame: .zero)
        // SwiftUI mounts this view during the open transition; the shared
        // player is already warm, so attaching the layer on the next runloop
        // turn keeps AVPlayerLayer setup off the mount's critical path.
        context.coordinator.scheduleAttach(layer: view.playerLayer, url: url, gravity: videoGravity)
        return view
    }

    func updateNSView(_ nsView: DynamicIslandArtworkVideoContainerView, context: Context) {
        context.coordinator.scheduleAttach(layer: nsView.playerLayer, url: url, gravity: videoGravity)
    }

    final class Coordinator {
        private var controller: DynamicIslandArtworkLoopController?
        private var currentURL: URL?
        private var attachTask: Task<Void, Never>?
        private var attachGeneration: Int = 0

        func scheduleAttach(layer: AVPlayerLayer, url: URL, gravity: AVLayerVideoGravity) {
            // Increment generation to invalidate any pending deferred attach
            attachGeneration &+= 1
            let generation = attachGeneration

            attachTask?.cancel()
            attachTask = Task { @MainActor in
                // Yield to let updateNSView run first if it's pending
                await Task.yield()
                // Only proceed if this is still the latest generation
                guard generation == attachGeneration else { return }
                attach(layer: layer, url: url, gravity: gravity)
            }
        }

        func attach(layer: AVPlayerLayer, url: URL, gravity: AVLayerVideoGravity) {
            layer.videoGravity = gravity

            if currentURL != url || controller == nil {
                detach()
                currentURL = url
                controller = DynamicIslandArtworkLoopRegistry.shared.player(for: url)
            }

            if layer.player !== controller?.player {
                layer.player = controller?.player
            }
        }

        func detach() {
            attachTask?.cancel()
            attachTask = nil
            guard let controller, let currentURL else { return }
            DynamicIslandArtworkLoopRegistry.shared.release(controller, for: currentURL)
            self.controller = nil
            self.currentURL = nil
        }

        deinit {
            detach()
        }
    }
}

struct DynamicIslandArtworkSourceView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.showLiveCanvasInDynamicIsland) private var showLiveCanvasInDynamicIsland

    let cornerRadius: CGFloat
    let contentMode: ContentMode
    var prefersVideo: Bool = true

    private var liveCanvasURL: URL? {
        guard showLiveCanvasInDynamicIsland, prefersVideo else { return nil }
        return musicManager.videoArtworkURL
    }

    var body: some View {
        Group {
            if let liveCanvasURL {
                DynamicIslandArtworkVideoView(url: liveCanvasURL, videoGravity: .resizeAspectFill)
            } else {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Music Player Components

/// The open player in E's language (docs/design/VISUAL-E.md §3): the 128 pt
/// cover with its light, and 12 to its right the hero title, the artist and
/// the bare transport glyphs. The seek is the island's bottom edge
/// (`NotchHomeView`), not part of this view.
struct MusicPlayerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID
    /// «Далее» stands beside the player, so its row keeps ⤮ and «Звук» only.
    var besideNext = false
    /// The secondary buttons show only while the pointer is over the player.
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace, isPlayerHovered: isHovering)
            MusicControlsView(isPlayerHovered: isHovering, besideNext: besideNext)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(DS.hover) { isHovering = hovering }
        }
    }
}

struct LyricsSidePanelView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Default(.pinLyricsWhenClosed) private var pinLyricsWhenClosed
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false
    /// E: no colour from the cover on text; it lives on the edge only.
    private var artistLineColor: Color { DSE.Palette.textSecondary }

    /// The colour a line has yet to be sung in. Tinted rather than plain grey so
    /// the unsung remainder still reads as part of the current line.
    private var lyricsStyle: SyncedLyricsStyle {
        SyncedLyricsStyle(
            sung: .white,
            unsung: artistLineColor.opacity(0.55),
            idle: DS.Palette.textTertiary,
            tint: artistLineColor
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                MicroLabel(String(localized: "Lyrics"))
                Spacer()
                pinButton
            }
            .frame(height: 12)
            .padding(.leading, 12)
            .padding(.bottom, 8)

            SyncedLyricsList(musicManager: musicManager, style: lyricsStyle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // E: the same hairline column as "Next", which takes this place when
        // lyrics are off; no card.
        .background(alignment: .leading) { Hairline(axis: .vertical) }
        .onHover { hovering in
            updateSuppression(for: hovering)
        }
        .onDisappear {
            updateSuppression(for: false)
        }
    }

    /// Keeps the current line under the notch once it closes again.
    ///
    /// Filled while pinned so the state reads at a glance from the panel that
    /// set it -- the strip it controls is only visible once the notch closes,
    /// which is exactly when this button is off screen.
    private var pinButton: some View {
        Button {
            withAnimation(.smooth) {
                pinLyricsWhenClosed.toggle()
            }
        } label: {
            Image(systemName: pinLyricsWhenClosed ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(pinLyricsWhenClosed ? artistLineColor : DS.Palette.textTertiary)
                .rotationEffect(.degrees(pinLyricsWhenClosed ? 0 : 45))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinLyricsWhenClosed
            ? "Stop showing lyrics under the closed notch"
            : "Keep showing lyrics under the closed notch")
        .accessibilityLabel(pinLyricsWhenClosed
            ? "Unpin lyrics from closed notch"
            : "Pin lyrics to closed notch")
    }

    // Prevent lyrics scrolling to close the expanded notch
    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}

/// The hero of «Сейчас»: the cover, 128 × 128, radius 10, aspect fill, no
/// rim, over its static light (L3) in the colour sampled once per picture.
/// Paused: the cover at 0.6 and its light at 35 %. No art: the 5 % square
/// with a note and the source's icon, in the neutral light.
struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID
    /// The source's icon shows on the cover only under the pointer.
    var isPlayerHovered = false
    @State private var light: Color

    /// The closed wing asks the same question, so the two always agree.
    private var hasArtwork: Bool { musicManager.showsRealArtwork }

    init(vm: DynamicIslandViewModel, albumArtNamespace: Namespace.ID, isPlayerHovered: Bool = false) {
        _vm = ObservedObject(wrappedValue: vm)
        self.albumArtNamespace = albumArtNamespace
        self.isPlayerHovered = isPlayerHovered
        // A cover already sampled (the closed wing did it) lights at once,
        // so opening does not recolour from neutral (M4).
        let music = MusicManager.shared
        let cached = music.showsRealArtwork ? LightColor.cachedLight(of: music.albumArt) : nil
        _light = State(initialValue: cached.map(LightColor.color) ?? DSE.Palette.lightNeutral)
    }

    var body: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
            artwork
                .frame(width: DSE.Size.cover, height: DSE.Size.cover)
                .clipShape(RoundedRectangle(cornerRadius: DSE.Radius.artOpen, style: .continuous))
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .albumArtFlip(angle: musicManager.flipAngle)
                .opacity(musicManager.isPlaying ? 1 : DSE.Opacity.dimmed)
                .overlay(alignment: .bottomTrailing) { sourceBadge }
        }
        .buttonStyle(PressDimStyle())
        .background {
            CoverGlow(color: light, strength: musicManager.isPlaying ? 1 : DSE.Opacity.pausedLight)
        }
        .animation(.easeOut(duration: 0.2), value: musicManager.isPlaying)
        // Once per picture, off the main thread; nothing runs in between.
        .task(id: ObjectIdentifier(musicManager.albumArt)) {
            let sampled = hasArtwork ? await LightColor.lightColor(of: musicManager.albumArt) : DSE.Palette.lightNeutral
            withAnimation(.easeOut(duration: 0.2)) { light = sampled }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if hasArtwork {
            DynamicIslandArtworkSourceView(cornerRadius: 0, contentMode: .fill)
        } else {
            ZStack {
                DSE.Palette.placeholder
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(DSE.Palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if vm.notchState == .open && (isPlayerHovered || !hasArtwork) {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .offset(x: 4, y: 4)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}

struct MusicControlsView: View {
    var isPlayerHovered = false
    /// «Далее» takes the space after the 178 pt column: the row keeps ⤮ and
    /// «Звук», and «…» lists the rest (VISUAL-E §2.5).
    var besideNext = false
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hudValue: Double = 0
    @State private var hudDragging: Bool = false
    @State private var hudLastDragged: Date = .distantPast
    @Default(.showShuffleAndRepeat) private var showCustomControls
    @Default(.musicControlSlots) private var slotConfig
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.enableLyrics) private var enableLyrics
    @Default(.showCalendar) private var showCalendar
    @Default(.islandLayout) private var islandLayout
    @Default(.showPlayerVolumeRow) private var showPlayerVolumeRow
    @State private var overflowToken = UUID()
    private let seekInterval: TimeInterval = 10

    /// The text column: the title at y 0, the artist under it, the transport
    /// row at y 90–130 (⏯'s 40 box; ⏮ ⏭ 28 at y 96–124), on the cover's axis.
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                songInfo(width: geo.size.width)
                Spacer(minLength: 0)
                Group {
                    if shouldShowControlHUDRow {
                        controlHUDRow
                    } else {
                        playbackControls
                    }
                }
                .frame(width: geo.size.width, height: 40, alignment: .leading)
            }
        }
        .frame(height: 130)
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        // What the row leaves out goes to «…»; set on change only.
        .onAppear { PlayerOverflow.shared.set(rowLayout.overflow, owner: overflowToken) }
        .onChange(of: rowLayout.overflow) { _, buttons in
            PlayerOverflow.shared.set(buttons, owner: overflowToken)
        }
        .onDisappear { PlayerOverflow.shared.clear(owner: overflowToken) }
    }

    /// The hover slots after the transport, and what «…» takes instead.
    private var rowLayout: PlayerControlsLayout.Row {
        let split = PlayerControlsLayout.split(
            displayedSlots,
            addingOutput: showMediaOutputControl,
            addingLyrics: true
        )
        let extras = split.leading + split.trailing
        guard besideNext else {
            return PlayerControlsLayout.Row(buttons: extras, showsVolume: showPlayerVolumeRow, overflow: [])
        }
        return PlayerControlsLayout.besideNext(extras, volume: showPlayerVolumeRow)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Hero 22, two lines at most, then a fade; never a marquee (§4.3).
            HeroTitle(
                text: musicManager.songTitle,
                width: width,
                color: musicManager.isPlaying ? DSE.Palette.text : DSE.Palette.secondary(contrast)
            )
            HStack(spacing: 4) {
                Text(verbatim: musicManager.controlsNote ?? musicManager.artistName)
                    .eText(.body)
                    .foregroundStyle(DSE.Palette.secondary(contrast))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if musicManager.isCurrentTrackExplicit {
                    Image(systemName: "e.square.fill")
                        .font(DSE.Typeface.caption)
                        .foregroundStyle(DSE.Palette.textTertiary)
                        .accessibilityLabel(Text("Explicit"))
                }
            }
            .frame(width: width, alignment: .leading)
            // The one-line lyrics under the artist, when the calendar takes the
            // side where the lyrics panel would go (not in the compact island,
            // which has no calendar column).
            if enableLyrics && showCalendar && islandLayout != .compact {
                let transition = AnyTransition.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )

                let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                let isInstrumentalBreak = musicManager.isInInstrumentalBreak

                if isInstrumentalBreak {
                    // The track is between verses, so mark it the way the side
                    // panel does instead of leaving a hole in the layout. Driven
                    // by the break itself rather than by the line being blank:
                    // during an intro there is no current line to blank out, so
                    // testing the text would miss it.
                    InstrumentalBreakNotes(fontSize: 10, weight: .regular)
                        .foregroundStyle(DSE.Palette.textSecondary)
                    .transition(transition)
                }

                if !isInstrumentalBreak, !line.isEmpty {
                    // E: no marquee; a long line ends at the column.
                    Text(verbatim: line)
                        .eText(.caption)
                        .foregroundStyle(DSE.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: width, alignment: .leading)
                        .id(line)
                        .transition(transition)
                        .animation(.easeInOut(duration: 0.32), value: line)
                }
            }
        }
    }

    /// ⏮ ⏯ ⏭ always, from the column's x 0, 8 apart; shuffle, repeat,
    /// output, lyrics, favourite and volume after them, 10 on, only while the
    /// pointer is over the player (or one of their popovers is open), so the
    /// player is calm otherwise (VISUAL-E §2.5).
    private var playbackControls: some View {
        let split = PlayerControlsLayout.split(
            displayedSlots,
            addingOutput: showMediaOutputControl,
            addingLyrics: true
        )
        let row = rowLayout
        let showsExtras = isPlayerHovered || vm.isMediaOutputPopoverActive
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array(split.transport.enumerated()), id: \.offset) { _, slot in
                    slotView(for: slot)
                }
            }
            .disabled(musicManager.controlsTakenBy != nil)
            .opacity(musicManager.controlsTakenBy == nil ? 1 : DS.heldControlsOpacity)

            HStack(spacing: 0) {
                ForEach(Array(row.buttons.enumerated()), id: \.offset) { _, slot in
                    slotView(for: slot)
                }
                if row.showsVolume {
                    PlayerVolumeButton()
                }
            }
            .opacity(showsExtras ? 1 : 0)
            .allowsHitTesting(showsExtras)
        }
        // Beside "Next" the row is ⏮ ⏯ ⏭ + ⤮ «Звук», exactly the 178 pt
        // column; without "Next" the extras may run on into empty space.
        .fixedSize()
        .animation(DS.hover, value: showsExtras)
    }

    private var shouldShowControlHUDRow: Bool {
        guard vm.notchState == .open else { return false }
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.enableSystemHUD] else { return false }
        guard !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] else { return false }

        switch coordinator.sneakPeek.type {
        case .volume:
            return Defaults[.enableVolumeHUD]
        case .brightness:
            return Defaults[.enableBrightnessHUD]
        case .backlight:
            return Defaults[.enableKeyboardBacklightHUD]
        default:
            return false
        }
    }

    private var controlHUDRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if !controlLeftIconName.isEmpty {
                Image(systemName: controlLeftIconName)
                    .font(DSE.Typeface.glyphOpen)
                    .foregroundStyle(DSE.Palette.text)
                    .frame(width: 22, height: 22, alignment: .center)
            }

            controlHUDSlider

            if !controlRightIconName.isEmpty {
                Image(systemName: controlRightIconName)
                    .font(DSE.Typeface.glyphOpen)
                    .foregroundStyle(DSE.Palette.text)
                    .frame(width: 22, height: 22, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { syncHUDValueIfNeeded(force: true) }
        .onChange(of: coordinator.sneakPeek.value) { _, _ in
            syncHUDValueIfNeeded(force: false)
        }
    }

    private var controlHUDSlider: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            CustomSlider(
                value: Binding(
                    get: { hudValue },
                    set: { newValue in
                        hudValue = newValue
                        updateControlHUDValue(newValue)
                    }
                ),
                range: 0...1,
                color: .white,
                dragging: $hudDragging,
                lastDragged: $hudLastDragged,
                onValueChange: { newValue in
                    updateControlHUDValue(newValue)
                },
                thumbSize: 10,
                // E: the line of light, 2 pt and 4 under the pointer (§2.10).
                restingTrackHeight: DSE.Size.line,
                draggingTrackHeight: DSE.Size.lineEngaged,
                hitHeight: 22
            )
            .frame(height: 22)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func syncHUDValueIfNeeded(force: Bool) {
        guard shouldShowControlHUDRow else { return }
        guard force || !hudDragging else { return }

        let target = Double(coordinator.sneakPeek.value)
        guard target != hudValue else { return }

        guard !force else {
            // First sync when the row appears: adopt the current level outright
            // rather than sliding up to it from wherever the slider last sat.
            hudValue = target
            return
        }

        // The keys deliver discrete steps (1/16 of the range each), and nothing
        // animated the fill between them, so the track jumped. Glide instead —
        // short enough to keep up with key auto-repeat, and interruptible, so a
        // held key reads as one continuous sweep rather than a queue of hops.
        withAnimation(.easeOut(duration: 0.18)) {
            hudValue = target
        }
    }

    private func updateControlHUDValue(_ newValue: Double) {
        let clamped = max(0, min(1, newValue))
        switch coordinator.sneakPeek.type {
        case .volume:
            SystemVolumeController.shared.setVolume(Float(clamped))
        case .brightness:
            SystemBrightnessController.shared.setBrightness(Float(clamped))
        case .backlight:
            SystemKeyboardBacklightController.shared.setLevel(Float(clamped))
        default:
            break
        }
    }

    private var controlLeftIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "speaker.slash" : "speaker.wave.1"
        case .brightness:
            return "sun.min.fill"
        case .backlight:
            return "light.min"
        default:
            return ""
        }
    }

    private var controlRightIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "" : "speaker.wave.3"
        case .brightness:
            return "sun.max.fill"
        case .backlight:
            return "light.max"
        default:
            return ""
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    /// E: an "on" control is white; colour never paints a glyph (§2.5).
    private var repeatIconColor: Color? {
        switch musicManager.repeatMode {
        case .off:
            return nil
        case .all, .one:
            return DSE.Palette.text
        }
    }

    private var displayedSlots: [MusicControlButton] {
        if showCustomControls {
            let normalized = slotConfig.normalized(allowingMediaOutput: showMediaOutputControl, isAppleMusicActive: musicManager.isAppleMusicActive, canFavorite: musicManager.activeSourceCanEverFavorite)
            return normalized.contains(where: { $0 != .none }) ? normalized : MusicControlButton.defaultLayout
        }

        switch musicSkipBehavior {
        case .track:
            return MusicControlButton.minimalLayout
        case .tenSecond:
            return [.none, .seekBackward, .playPause, .seekForward, .none]
        }
    }

    @ViewBuilder
    private func slotView(for control: MusicControlButton) -> some View {
        switch control {
        case .none:
            Spacer(minLength: 0)
        case .playPause:
            HoverButton(
                icon: musicManager.isPlaying ? (musicManager.isLiveStream ? "stop.fill" : "pause.fill") : "play.fill",
                iconColor: DSE.Palette.text,
                scale: .large
            ) {
                MusicManager.shared.togglePlay()
            }
        case .trackBackward:
            playbackButton(
                icon: "backward.fill",
                press: nil,
                trigger: skipGestureTrigger(for: .trackBackward),
                skipDirection: .backward
            ) {
                musicManager.previousTrack()
            }
        case .trackForward:
            playbackButton(
                icon: "forward.fill",
                press: nil,
                trigger: skipGestureTrigger(for: .trackForward),
                skipDirection: .forward
            ) {
                musicManager.nextTrack()
            }
        case .seekBackward:
            playbackButton(
                icon: "gobackward.10",
                press: .wiggle(.counterClockwise),
                trigger: skipGestureTrigger(for: .seekBackward)
            ) {
                musicManager.seek(by: -seekInterval)
            }
        case .seekForward:
            playbackButton(
                icon: "goforward.10",
                press: .wiggle(.clockwise),
                trigger: skipGestureTrigger(for: .seekForward)
            ) {
                musicManager.seek(by: seekInterval)
            }
        case .shuffle:
            HoverButton(
                icon: "shuffle",
                iconColor: musicManager.isShuffled ? DSE.Palette.text : nil,
                scale: .medium
            ) {
                MusicManager.shared.toggleShuffle()
            }
        case .repeatMode:
            HoverButton(
                icon: repeatIcon,
                iconColor: repeatIconColor,
                scale: .medium
            ) {
                MusicManager.shared.toggleRepeat()
            }
        case .mediaOutput:
            MediaOutputPickerButton()
        case .airPlay:
            AirPlayPickerButton()
        case .lyrics:
            HoverButton(
                icon: enableLyrics ? "quote.bubble.fill" : "quote.bubble",
                iconColor: enableLyrics ? DSE.Palette.text : nil,
                scale: .medium
            ) {
                LyricsConsent.toggle()
            }
        case .likeTrack:
            LikeTrackControl { presentation, toggle in
                HoverButton(
                    icon: presentation.iconName,
                    iconColor: presentation.isActive ? DSE.Palette.text : nil,
                    scale: .medium
                ) {
                    toggle()
                }
            }
        }
    }

    private struct SkipTrigger {
        let token: Int
        /// nil for the track buttons: the pulse advances the skip glyph rather
        /// than moving the button.
        let pressEffect: HoverButton.PressEffect?
    }

    private func playbackButton(
        icon: String,
        press: HoverButton.PressEffect?,
        trigger: SkipTrigger?,
        skipDirection: SkipTrackGlyph.Direction? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HoverButton(
            icon: icon,
            scale: .medium,
            pressEffect: press,
            externalTriggerToken: trigger?.token,
            externalTriggerEffect: trigger?.pressEffect,
            skipDirection: skipDirection
        ) {
            action()
        }
    }

    private func skipGestureTrigger(for control: MusicControlButton) -> SkipTrigger? {
        guard let pulse = musicManager.skipGesturePulse else { return nil }

        switch control {
        case .trackBackward where pulse.behavior == .track && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: nil)
        case .trackForward where pulse.behavior == .track && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: nil)
        case .seekBackward where pulse.behavior == .tenSecond && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.counterClockwise))
        case .seekForward where pulse.behavior == .tenSecond && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.clockwise))
        default:
            return nil
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.showCalendar) private var showCalendar
    @Default(.islandLayout) private var islandLayout
    @Default(.enableLyrics) private var enableLyrics
    @Default(.lyricsPanelWidth) private var lyricsPanelWidth
    @Default(.lyricsPanelOffset) private var lyricsPanelOffset
    @State private var showCalendarDeferred = false
    @State private var calendarSyncGeneration = 0
    let albumArtNamespace: Namespace.ID

    /// Whether the music player should actively display (enabled AND has real content).
    private var shouldShowMusicPlayer: Bool {
        showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer || musicManager.hasActiveSession)
    }

    private var shouldShowSideLyrics: Bool {
        shouldShowMusicPlayer && enableLyrics && !showsCalendarColumn
    }

    /// The compact one-row player carries "Next" itself, so there is no
    /// calendar column beside it.
    private var showsCalendarColumn: Bool {
        showCalendar && !(islandLayout == .compact && shouldShowMusicPlayer)
    }

    private var nowLayout: NowTabLayout {
        NowTabLayout.resolve(
            playerShown: shouldShowMusicPlayer,
            isPlaying: musicManager.isPlaying,
            playerIdle: musicManager.isPlayerIdle,
            calendarOn: showCalendar,
            compact: islandLayout == .compact
        )
    }
    
    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
                    .onAppear {
                        syncCalendarDeferred()
                    }
                    .onChange(of: showCalendar) { _, newValue in
                        syncCalendarDeferred()
                    }
            }
        }
        .transition(.opacity)
    }

    private func syncCalendarDeferred() {
        guard showCalendar else {
            showCalendarDeferred = false
            calendarSyncGeneration &+= 1
            return
        }
        let generation = calendarSyncGeneration
        DispatchQueue.main.async {
            if generation == calendarSyncGeneration {
                showCalendarDeferred = true
            }
        }
    }

    private var mainContent: some View {
        Group {
            if islandLayout == .compact && shouldShowMusicPlayer {
                // Compact: the player in one row, in a lower island.
                CompactPlayerRow(showsNext: showCalendar && showCalendarDeferred)
                    .padding(.horizontal, 4)
            } else if shouldShowSideLyrics {
                sideLyricsContent
            } else {
                switch nowLayout {
                case .idle:
                    // Nothing playing: the last track greyed with ▶, and
                    // "Next" across instead of an empty player.
                    VStack(spacing: 8) {
                        IdlePlayerStrip()
                        if nowLayout.showsNext(deferralDone: showCalendarDeferred) {
                            NextEventsCard(limit: 2)
                        }
                    }
                case .nextOnly:
                    if islandLayout == .compact {
                        // The lower compact island is too low for the card.
                        NextEventsCard(limit: NextEvents.compactLimit, style: .headedLines)
                    } else {
                        NextEventsCard()
                    }
                case .nothing where !mirrorIsVisible:
                    // An empty tab used to be just black.
                    DSEmptyState(
                        symbol: "music.note",
                        title: String(localized: "Nothing to show here"),
                        message: String(localized: "Turn on the player or the calendar for this tab in Settings."),
                        actionTitle: String(localized: "Open Settings"),
                        action: { SettingsWindowController.shared.showWindow() }
                    )
                case .player, .nothing:
                    // E (VISUAL-E §3): the cover and its text column, then
                    // "Next" as a 240 pt line of time whose hairline sits 12
                    // after the column.
                    HStack(alignment: .top, spacing: 12) {
                        if shouldShowMusicPlayer {
                            // Not raised over "Next": nothing of the player
                            // draws into its column.
                            MusicPlayerView(
                                albumArtNamespace: albumArtNamespace,
                                besideNext: nowLayout.showsNext(deferralDone: showCalendarDeferred)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        }

                        if nowLayout.showsNext(deferralDone: showCalendarDeferred) {
                            NextEventsCard()
                                .frame(width: shouldShowMusicPlayer ? 240 : nil)
                        }

                        if mirrorIsVisible && islandLayout != .compact {
                            cameraPreview
                        }
                    }
                    // The island keeps its full height, so the seek is its edge.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .transition(.opacity.animation(.smooth.speed(0.9))
            .combined(with: .move(edge: .top)))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
        // The home view's main padding. E starts the content right under the
        // header (frame y 40); the compact island keeps its 8.
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .padding(.top, islandLayout == .compact ? 8 : 0)
        .overlay(alignment: .bottom) {
            if showsSeekEdge {
                seekEdge
                    .padding(.horizontal, 8)
                    // The island's own bottom edge: 12 below this view.
                    .offset(y: Self.islandBottomInset)
            }
        }
    }

    /// What lies between this view and the island's bottom edge (the open
    /// island's bottom padding in ContentView).
    private static let islandBottomInset: CGFloat = 12

    /// The full player is on the tab; the compact row draws its own seek.
    private var showsSeekEdge: Bool {
        guard shouldShowMusicPlayer, !(islandLayout == .compact) else { return false }
        if shouldShowSideLyrics { return true }
        if case .player = nowLayout { return true }
        return false
    }

    /// No tick while paused, stopped or live: the edge is drawn once.
    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }

    /// The seek is the island's bottom edge (VISUAL-E §2.4, R6). It steps
    /// once a second only while open and playing (this view exists only
    /// while open); otherwise nothing ticks. One timeline in every state, so
    /// play, pause and rate changes keep the edge's scrub and drop state.
    private var seekEdge: some View {
        TimelineView(.animation(minimumInterval: 1, paused: isProgressTimelinePaused)) { timeline in
            // A paused timeline keeps its last date; never read before the
            // player's own latest report.
            seekEdge(at: max(timeline.date, musicManager.timestampDate))
        }
    }

    private func seekEdge(at date: Date) -> some View {
        let duration = musicManager.songDuration
        let position = musicManager.estimatedPlaybackPosition(at: date)
        return SeekEdge(
            progress: duration > 0 ? position / duration : 0,
            duration: duration,
            // A seek would reach the video that holds the controls.
            isEnabled: musicManager.controlsTakenBy == nil,
            liveLabel: musicManager.isLiveStream ? String(localized: "LIVE") : nil,
            onSeek: { MusicManager.shared.seek(to: $0) }
        )
    }

    private var sideLyricsContent: some View {
        HStack(alignment: .top, spacing: SideLyricsLayout.hStackSpacing) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)
                .frame(minWidth: SideLyricsLayout.minimumPlayerWidth, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            LyricsSidePanelView()
                .frame(width: max(0, lyricsPanelWidth), alignment: .topLeading)
                .padding(.leading, max(0, -lyricsPanelOffset))
                .offset(x: lyricsPanelOffset)

            if mirrorIsVisible {
                cameraPreview
                    .frame(minWidth: SideLyricsLayout.minimumMirrorWidth, maxWidth: .infinity)
            }
        }
    }

    private var mirrorIsVisible: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.notchState == .open
    }

    private var cameraPreview: some View {
        CameraPreviewView(webcamManager: webcamManager)
            .scaledToFit()
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
    }

}

/// The track title as the player's hero (VISUAL-E §1.4 `hero`, §4.3): 22 pt
/// semibold, up to two lines. A title longer than that runs on in the second
/// line, which ends in a 10 pt fade at the column's edge: never «…», never a
/// marquee. The tooltip holds the full title.
struct HeroTitle: View {
    let text: String
    let width: CGFloat
    var color: Color = DSE.Palette.text

    static let lineHeight: CGFloat = 26
    private static let fade: CGFloat = 10

    var body: some View {
        let lines = HeroTitleLines.split(text, width: width)
        VStack(alignment: .leading, spacing: 0) {
            line(lines.first, fades: lines.rest == nil && lines.firstOverflows)
            if let rest = lines.rest {
                line(rest, fades: lines.restOverflows)
            }
        }
        .foregroundStyle(color)
        .frame(width: max(width, 0), alignment: .leading)
        .help(text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    private func line(_ string: String, fades: Bool) -> some View {
        Text(verbatim: string)
            .eText(.hero)
            .lineLimit(1)
            .fixedSize()
            .frame(width: max(width, 0), height: Self.lineHeight, alignment: .leading)
            .clipped()
            .mask {
                if fades {
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.fade)
                    }
                } else {
                    Rectangle()
                }
            }
    }
}

/// Where the hero title breaks: the words that fit the first line, and the
/// rest on one second line (which fades if it is longer than the column).
enum HeroTitleLines {
    struct Lines: Equatable {
        var first: String
        var rest: String?
        var firstOverflows = false
        var restOverflows = false
    }

    private static let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
    /// One entry: the title changes once per track, not per frame.
    private static var cache: (key: String, width: CGFloat, lines: Lines)?

    static func width(of string: String) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font, .kern: -0.5]).width)
    }

    static func split(_ text: String, width: CGFloat) -> Lines {
        if let cache, cache.key == text, cache.width == width { return cache.lines }
        let lines = compute(text, width: width)
        cache = (text, width, lines)
        return lines
    }

    private static func compute(_ text: String, width: CGFloat) -> Lines {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard width > 0, self.width(of: title) > width else { return Lines(first: title) }
        let words = title.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var first = ""
        var used = 0
        for word in words {
            let candidate = first.isEmpty ? word : first + " " + word
            guard self.width(of: candidate) <= width else { break }
            first = candidate
            used += 1
        }
        // A first word wider than the column: one line, faded.
        guard used > 0 else { return Lines(first: title, firstOverflows: true) }
        let rest = words.dropFirst(used).joined(separator: " ")
        guard !rest.isEmpty else { return Lines(first: first) }
        return Lines(first: first, rest: rest, restOverflows: self.width(of: rest) > width)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    let isLiveStream: Bool
    var onValueChange: (Double) -> Void
    var labelLayout: TimeLabelLayout = .stacked
    var trailingLabel: TrailingLabel = .duration
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14
    /// When set, bypasses Defaults[.sliderColor] (used by lock screen appearance).
    var tintOverride: Color? = nil
    /// Greys the track out until it is reached for, the way Apple's transport
    /// sliders do. Opt-in: the notch's own slider is meant to carry the album
    /// colour at rest.
    var desaturatesWhenIdle: Bool = false
    /// The height that takes clicks around the track (see CustomSlider);
    /// 0 keeps the slider as tall as its track.
    var hitHeight: CGFloat = MusicSliderView.seekHitHeight

    enum TimeLabelLayout {
        case stacked
        case inline
    }

    enum TrailingLabel {
        case duration
        case remaining
    }

    var body: some View {
        Group {
            if isLiveStream {
                liveStreamView
            } else {
                switch labelLayout {
                case .stacked:
                    stackedContent
                case .inline:
                    inlineContent
                }
            }
        }
        .onAppear {
            guard !isLiveStream else { return }
            guard !dragging else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition())
        }
        .onChange(of: currentDate) { newDate in
            guard !isLiveStream else { return }
            guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition(at: newDate))
        }
        .onChange(of: isPlaying) { _, playing in
            // Snap slider to the exact position when music pauses so
            // the in-flight animation doesn't coast past the true value.
            if !playing {
                sliderValue = MusicManager.shared.estimatedPlaybackPosition()
            }
        }
        .onChange(of: isLiveStream) { isLive in
            if isLive {
                sliderValue = 0
            }
        }
    }

    private func setSliderValueWithoutAnimation(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sliderValue = value
        }
    }

    private var stackedContent: some View {
        // The slider's taller hit area already spaces the times.
        VStack(spacing: max(0, 6 - (sliderFrameHeight - max(restingTrackHeight, draggingTrackHeight)))) {
            sliderCore
                .frame(height: sliderFrameHeight)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(trailingTimeText)
            }
            .fontWeight(.medium)
            .foregroundColor(timeLabelColor)
            .font(.system(size: 11, weight: .medium, design: .default).monospacedDigit())
        }
    }

    private var inlineContent: some View {
        HStack(spacing: 6) {
            Text(timeString(from: sliderValue))
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 36, alignment: .leading)

            sliderCore
                .frame(height: sliderFrameHeight)
                .frame(maxWidth: .infinity)

            Text(trailingTimeText)
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 42, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var liveStreamView: some View {
        switch labelLayout {
        case .stacked:
            LiveStreamProgressIndicator(tint: sliderTint)
                .frame(maxWidth: .infinity)
                .frame(height: sliderFrameHeight)
                
        case .inline:
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: 36)
                LiveStreamProgressIndicator(tint: sliderTint)
                    .frame(maxWidth: .infinity)
                    .frame(height: sliderFrameHeight)

                Spacer()
                    .frame(width: 42)
            }
        }
    }

    @ViewBuilder
    private var sliderCore: some View {
        if hasUsableDuration {
            CustomSlider(
                value: $sliderValue,
                range: 0 ... duration,
                color: sliderTint,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange,
                restingTrackHeight: restingTrackHeight,
                draggingTrackHeight: draggingTrackHeight,
                desaturatesWhenIdle: desaturatesWhenIdle,
                hitHeight: hitHeight
            )
        } else {
            // Non-interactive fallback matching CustomSlider's idle appearance:
            // gray track + colored fill at current estimated position. No seeking
            // allowed until hasUsableDuration becomes true.
            // Use estimated playback position and a surrogate duration so the
            // fill renders meaningfully even before the real duration arrives.
            let estimatedPosition: Double = {
                guard isPlaying else { return min(elapsedTime, duration) }
                let timeDifference = currentDate.timeIntervalSince(timestampDate)
                let estimated = elapsedTime + (timeDifference * playbackRate)
                return min(max(0, estimated), duration)
            }()
            let surrogateDuration = max(1, estimatedPosition * 2, elapsedTime * 2)
            let progress = surrogateDuration > 0 ? min(max(estimatedPosition / surrogateDuration, 0), 1) : 0
            GeometryReader { geometry in
                let width = geometry.size.width
                let trackHeight = restingTrackHeight
                let filledWidth = max(1, width) * progress
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.gray.opacity(0.3))
                        .frame(height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                        .transaction { $0.disablesAnimations = true }
                    Rectangle()
                        .fill(sliderTint)
                        .frame(width: filledWidth, height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                        .transaction { $0.disablesAnimations = true }
                }
            }
            .frame(height: restingTrackHeight)
        }
    }

    private var sliderTint: Color {
        if let tintOverride {
            return tintOverride
        }
        switch Defaults[.sliderColor] {
        case .albumArt:
            return Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
        case .accent:
            return .accentColor
        case .white:
            return .white
        }
    }

    private var timeLabelColor: Color {
        if let tintOverride {
            return tintOverride
        }
        return Defaults[.playerColorTinting]
            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
            : DS.Palette.textTertiary
    }

    /// Whether the reported duration is one a track could actually have.
    ///
    /// Senders do not always report a usable one — a live stream has none to
    /// give, and some hand back a sentinel or an epoch timestamp instead. The
    /// remaining-time label subtracts the position from it and formats the
    /// result as hours, so an epoch came out on screen as `-1732919508:00:54`.
    /// A day is well past any track and well short of those.
    private var hasUsableDuration: Bool {
        duration.isFinite && duration > 0 && duration <= 24 * 60 * 60
    }

    /// Shown in place of a time there is no sensible value for, rather than a
    /// formatted impossibility.
    private static let unknownTime = "--:--"

    private var trailingTimeText: String {
        guard hasUsableDuration else { return Self.unknownTime }

        switch trailingLabel {
        case .duration:
            return timeString(from: duration)
        case .remaining:
            // A position that is not a position cannot be subtracted from
            // anything, and a negative one would inflate what is left rather
            // than reduce it.
            guard sliderValue.isFinite, sliderValue >= 0 else { return Self.unknownTime }

            let remaining = timeString(from: max(duration - sliderValue, 0))
            // The minus belongs to a time, not to the absence of one: prefixing
            // it unconditionally turned --:-- into ---:--.
            return remaining == Self.unknownTime ? remaining : "-" + remaining
        }
    }

    private var inlineLabelFont: Font {
        .system(size: 11, weight: .medium, design: .default).monospacedDigit()
    }

    /// Clicks land within this height around the track (see CustomSlider).
    static let seekHitHeight: CGFloat = 20

    private var sliderFrameHeight: CGFloat {
        CustomSlider.frameHeight(resting: restingTrackHeight, dragging: draggingTrackHeight, hit: hitHeight)
    }

    func timeString(from seconds: Double) -> String {
        // Int(_:) traps on a value too large to represent, and NaN has no
        // meaning here either; neither belongs on screen as a time.
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else {
            return Self.unknownTime
        }

        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }

}


struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var thumbSize: CGFloat = 12
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14
    /// See `MusicSliderView.desaturatesWhenIdle`.
    var desaturatesWhenIdle: Bool = false
    /// The height that takes clicks, taller than the track: a thin track was
    /// only caught by a click right on it.
    var hitHeight: CGFloat = 0
    
    @State private var isHovering: Bool = false
    @Default(.enableRealTimeWaveform) var enableRealTimeWaveform
    @Default(.enableWaveformScrubber) var enableWaveformScrubber

    private var isEngaged: Bool { dragging || isHovering }

    private var trackSaturation: Double {
        desaturatesWhenIdle && !isEngaged ? 0 : 1
    }

    private var trackOpacity: Double {
        guard desaturatesWhenIdle else { return 1 }
        return isEngaged ? 1 : 0.82
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Thicker under the pointer, not only while dragging, so the track
            // shows it can be moved before it is grabbed.
            let trackHeight = Self.trackHeight(engaged: isEngaged, resting: restingTrackHeight, dragging: draggingTrackHeight)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * max(1, width)
            
            let showScrubber = isHovering && enableRealTimeWaveform && enableWaveformScrubber

            ZStack(alignment: .bottomLeading) {
                // Background track
                if showScrubber {
                    RealTimeWaveformScrubberView(
                        color: color,
                        secondaryColor: Defaults[.coloredSpectrogram] ? Color(nsColor: MusicManager.shared.secondaryColor) : nil,
                        progress: progress,
                        minHeight: trackHeight
                    )
                    .frame(height: trackHeight * 3.5)
                    .offset(y: trackHeight * 0.2)
                    .transaction { $0.disablesAnimations = true }
                } else {
                    Rectangle()
                        .fill(.gray.opacity(0.3))
                        .frame(height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                        .transaction { $0.disablesAnimations = true }
                }

                // Filled track
                if !showScrubber {
                    Rectangle()
                        .fill(color)
                        .frame(width: filledTrackWidth, height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                        .transaction { $0.disablesAnimations = true }
                }
            }
            // The track swells from its middle, so it grows into the space
            // above and below equally instead of climbing off the baseline --
            // which is also what leaves it level with the times beside it.
            // The waveform scrubber is the exception: it is 3.5x the track and
            // is drawn to rise out of the bar, so it stays bottom-anchored.
            .frame(
                height: Self.frameHeight(resting: restingTrackHeight, dragging: draggingTrackHeight, hit: hitHeight),
                alignment: showScrubber ? .bottom : .center
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .saturation(trackSaturation)
            // Kept well above the volume bar's resting brightness: a seek bar
            // that fades as far as that one reads as disabled rather than idle.
            .opacity(trackOpacity)
            .animation(.easeOut(duration: 0.2), value: trackSaturation)
            .animation(.easeOut(duration: 0.2), value: trackOpacity)
            .animation(.bouncy.speed(1.4), value: dragging)
            .animation(DS.hover, value: isHovering)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
        }
    }

    static func trackHeight(engaged: Bool, resting: CGFloat, dragging: CGFloat) -> CGFloat {
        engaged ? dragging : resting
    }

    static func frameHeight(resting: CGFloat, dragging: CGFloat, hit: CGFloat) -> CGFloat {
        max(resting, dragging, hit)
    }
}

/// The volume button among the player's secondary buttons: the volume row
/// in a popover, instead of a row that always took space under the player.
struct PlayerVolumeButton: View {
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @State private var isPopoverPresented = false
    @State private var popoverToken = UUID()
    @EnvironmentObject private var vm: DynamicIslandViewModel

    var body: some View {
        HoverButton(
            icon: volumeModel.isMuted || volumeModel.level <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill",
            iconColor: isPopoverPresented ? DSE.Palette.text : nil,
            scale: .medium
        ) {
            isPopoverPresented.toggle()
        }
        .help(String(localized: "Volume"))
        .accessibilityLabel(Text("Volume"))
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            PlayerVolumeRow(showsOutput: false)
                .frame(width: 220)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
        }
        .onChange(of: isPopoverPresented) { _, presented in
            // Keeps the island open while the popover is (see MediaOutputPickerButton).
            vm.setMediaOutputPopoverActive(presented, token: popoverToken)
        }
        .onDisappear {
            vm.setMediaOutputPopoverActive(false, token: popoverToken)
        }
    }
}

/// Volume, output device and "Open player".
private struct PlayerVolumeRow: View {
    /// The volume track took clicks only within its 6 points.
    static let hitHeight: CGFloat = 24
    var showsOutput = true
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @State private var dragging = false
    @State private var lastDragged = Date.distantPast

    var body: some View {
        HStack(spacing: 8) {
            Button {
                volumeModel.toggleMute()
            } label: {
                Image(systemName: volumeModel.isMuted || volumeModel.level <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(volumeModel.isMuted ? "Unmute" : "Mute")

            CustomSlider(
                value: Binding(
                    get: { Double(volumeModel.level) },
                    set: { volumeModel.setVolume(Float($0)) }
                ),
                range: 0...1,
                color: .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: { volumeModel.setVolume(Float($0)) },
                thumbSize: 9,
                restingTrackHeight: 4,
                draggingTrackHeight: 7,
                hitHeight: PlayerVolumeRow.hitHeight
            )
            .frame(height: PlayerVolumeRow.hitHeight)
            .accessibilityLabel(Text("Volume"))

            if showsOutput {
                MediaOutputPickerButton()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 16)
            }

            Button {
                MusicManager.shared.openMusicApp()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open player")
            .accessibilityLabel(Text("Open player"))
        }
        .frame(height: 16)
        .padding(.horizontal, 6)
    }
}

private struct MediaOutputPickerButton: View {
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @State private var isPopoverPresented = false
    @State private var popoverToken = UUID()
    @EnvironmentObject private var vm: DynamicIslandViewModel

    var body: some View {
        HoverButton(icon: buttonIcon, iconColor: isPopoverPresented ? DSE.Palette.text : nil, scale: .medium) {
            isPopoverPresented.toggle()
            if isPopoverPresented {
                routeManager.refreshDevices()
            }
        }
        .accessibilityLabel("Media output")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            MediaOutputSelectorPopover(
                routeManager: routeManager,
                volumeModel: volumeModel,
                onHoverChanged: { _ in }
            ) {
                isPopoverPresented = false
                updatePopoverActivity()
            }
        }
        .onAppear {
            routeManager.refreshDevices()
        }
        .onChange(of: isPopoverPresented) { _, _ in
            updatePopoverActivity()
        }
        .onDisappear {
            vm.setMediaOutputPopoverActive(false, token: popoverToken)
        }
    }

    private var buttonIcon: String {
        routeManager.activeDevice?.iconName ?? "speaker.wave.2"
    }

    /// Reports whether this picker's popover is open, so the notch knows not to
    /// auto-close while it is.
    ///
    /// Keyed by a token unique to this presenter: several pickers can exist at
    /// once and the notch has to stay open while *any* of them is showing, so
    /// the view model tracks a set of open popovers rather than one flag that
    /// the second picker to close would clear on behalf of the first.
    private func updatePopoverActivity() {
        // Presentation alone, deliberately. Also requiring the pointer to be over
        // the popover raced the notch's own hover tracking: the popover is a
        // separate window, so moving into it reads as leaving the notch, and any
        // moment before the popover reported the pointer let the auto-close timer
        // shut the notch and take the popover with it. This is what the stats,
        // timer and clipboard popovers already do.
        vm.setMediaOutputPopoverActive(isPopoverPresented, token: popoverToken)
    }
}

private struct AirPlayPickerButton: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared
    @State private var isPopoverPresented = false
    @State private var popoverToken = UUID()
    @EnvironmentObject private var vm: DynamicIslandViewModel

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    var body: some View {
        HoverButton(icon: "airplayaudio", iconColor: isPopoverPresented ? DSE.Palette.text : nil, scale: .medium) {
            isPopoverPresented.toggle()
            if isPopoverPresented {
                Task { await airPlayManager.refreshDevices(afterClick: true) }
            }
        }
        .accessibilityLabel("AirPlay")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            AirPlaySelectorPopover(
                airPlayManager: airPlayManager,
                onHoverChanged: { _ in }
            ) {
                isPopoverPresented = false
                updatePopoverActivity()
            }
        }
        .onAppear {
            if isAppleMusicActive {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .onChange(of: isPopoverPresented) { _, _ in
            updatePopoverActivity()
        }
        .onChange(of: musicManager.bundleIdentifier) { _, newBundle in
            if newBundle == "com.apple.Music" {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .onDisappear {
            vm.setMediaOutputPopoverActive(false, token: popoverToken)
        }
    }

    /// Reports whether this picker's popover is open, so the notch knows not to
    /// auto-close while it is.
    ///
    /// Keyed by a token unique to this presenter: several pickers can exist at
    /// once and the notch has to stay open while *any* of them is showing, so
    /// the view model tracks a set of open popovers rather than one flag that
    /// the second picker to close would clear on behalf of the first.
    private func updatePopoverActivity() {
        // Presentation alone, deliberately. Also requiring the pointer to be over
        // the popover raced the notch's own hover tracking: the popover is a
        // separate window, so moving into it reads as leaving the notch, and any
        // moment before the popover reported the pointer let the auto-close timer
        // shut the notch and take the popover with it. This is what the stats,
        // timer and clipboard popovers already do.
        vm.setMediaOutputPopoverActive(isPopoverPresented, token: popoverToken)
    }
}

struct MediaOutputSelectorPopover: View {
    @ObservedObject var routeManager: AudioRouteManager
    @ObservedObject var volumeModel: MediaOutputVolumeViewModel
    var onHoverChanged: (Bool) -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            volumeSection
            Divider()
            devicesSection
        }
        .frame(width: 240)
        .padding(16)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    volumeModel.toggleMute()
                } label: {
                    // Half the chip, which is about where Apple puts a glyph
                    // inside a circular one. At 18pt the speaker's waves ran
                    // right up against the edge of the circle.
                    Image(systemName: volumeIconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.18))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(volumeModel.level) },
                        set: { newValue in
                            volumeModel.setVolume(Float(newValue))
                        }
                    ),
                    in: 0 ... 1
                )
                .tint(.accentColor)
            }

            HStack {
                Text("Output volume")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(volumePercentage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output devices")
                .font(.caption)
                .foregroundColor(.secondary)

            if routeManager.devices.isEmpty {
                Text("No audio outputs available")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(routeManager.devices) { device in
                            Button {
                                routeManager.select(device: device)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(device.name)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if device.id == routeManager.activeDeviceID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(device.id == routeManager.activeDeviceID ? Color.primary.opacity(0.12) : .clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }
        }
    }

    private var volumeIconName: String {
        if volumeModel.isMuted || volumeModel.level <= 0.001 {
            return "speaker.slash.fill"
        } else if volumeModel.level < 0.33 {
            return "speaker.wave.1.fill"
        } else if volumeModel.level < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private var volumePercentage: String {
        "\(Int(round(volumeModel.level * 100)))%"
    }
}

struct AirPlaySelectorPopover: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    var onHoverChanged: (Bool) -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AirPlay")
                .font(.caption)
                .foregroundColor(.secondary)

            if airPlayManager.devices.isEmpty {
                Text("No AirPlay devices found")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(airPlayManager.devices) { device in
                            VStack(spacing: 4) {
                                Button {
                                    Task { await airPlayManager.toggleDevice(device) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: device.iconName)
                                            .font(.system(size: 14, weight: .medium))
                                        Text(device.name)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        if device.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(device.isSelected ? Color.primary.opacity(0.12) : .clear)
                                    )
                                }
                                .buttonStyle(.plain)

                                if device.isSelected {
                                    AirPlayVolumeSlider(
                                        airPlayManager: airPlayManager,
                                        deviceID: device.id
                                    )
                                    .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 240)
        .padding(16)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }
}

/// Local @State slider decoupled from the manager's @Published state.
/// This prevents SwiftUI from resetting the slider position when other
/// published properties on the manager change during a drag.
struct AirPlayVolumeSlider: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    let deviceID: String

    @State private var sliderValue: Double = 0
    @State private var isSyncing = false

    var body: some View {
        Slider(value: $sliderValue, in: 0...100)
            .tint(.accentColor)
            .onAppear {
                isSyncing = true
                sliderValue = Double(airPlayManager.currentVolume(for: deviceID))
                isSyncing = false
            }
            .onChange(of: sliderValue) { _, newValue in
                guard !isSyncing else { return }
                airPlayManager.setVolume(Int(newValue), for: deviceID)
            }
    }
}

final class MediaOutputVolumeViewModel: ObservableObject {
    @Published var level: Float
    @Published var isMuted: Bool

    private let controller: SystemVolumeController
    private var cancellables: Set<AnyCancellable> = []

    init(controller: SystemVolumeController = .shared) {
        self.controller = controller
        controller.start()
        level = controller.currentVolume
        isMuted = controller.isMuted

        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let value = notification.userInfo?["value"] as? Float,
                      let muted = notification.userInfo?["muted"] as? Bool else { return }
                self.level = value
                self.isMuted = muted
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemAudioRouteDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFromController()
            }
            .store(in: &cancellables)
    }

    /// How long the volume HUD stays suppressed after a change made from one of
    /// our own controls. Refreshed on every change, so a drag holds it off until
    /// shortly after the last movement.
    private static let ownControlHUDSuppression: TimeInterval = 1.5

    func setVolume(_ value: Float) {
        // The user is already looking at a volume control. Letting the change
        // raise the notch's volume HUD puts a second slider on screen and swaps
        // out the content this one is anchored to, tearing the popover down
        // mid-drag -- which is why the slider could not be dragged at all.
        HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: Self.ownControlHUDSuppression)
        level = value
        if value > 0 {
            isMuted = false
        }
        controller.setVolume(value)
    }

    func toggleMute() {
        HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: Self.ownControlHUDSuppression)
        isMuted.toggle()
        controller.toggleMute()
    }

    private func syncFromController() {
        level = controller.currentVolume
        isMuted = controller.isMuted
    }
}

#Preview {
    NotchHomeView(
        albumArtNamespace: Namespace().wrappedValue
    )
    .environmentObject(DynamicIslandViewModel())
}
