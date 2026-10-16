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

import AppKit
import Defaults
import SwiftUI

/// The player in one row, for the compact island (docs/PLAN-DESIGN.md
/// §3.10): artwork, title and artist over a thin progress line you can
/// click or drag to seek, ⏮ ⏯ ⏭, the volume button while the pointer is
/// over the row, and the next two events at the end of the row.
struct CompactPlayerRow: View {
    /// Whether "Next" closes the row (the calendar is on).
    var showsNext = false
    @ObservedObject private var musicManager = MusicManager.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Default(.showPlayerVolumeRow) private var showsVolume
    @State private var isHovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            CompactPlayerRowContent(
                artwork: musicManager.albumArt,
                title: musicManager.hasActiveSession ? musicManager.songTitle : String(localized: "Nothing playing"),
                artist: musicManager.hasActiveSession ? musicManager.artistName : "",
                progress: CompactPlayerRowContent.progress(
                    elapsed: musicManager.estimatedPlaybackPosition(at: context.date),
                    duration: musicManager.songDuration
                ),
                isPlaying: musicManager.isPlaying,
                duration: musicManager.songDuration,
                onSeek: musicManager.isLiveStream ? nil : { MusicManager.shared.seek(to: $0) },
                controlsNote: musicManager.controlsNote,
                onPrevious: { musicManager.previousTrack() },
                onPlayPause: { MusicManager.shared.togglePlay() },
                onNext: { musicManager.nextTrack() },
                onOpenPlayer: { MusicManager.shared.openMusicApp() },
                volumeControl: showsVolume ? AnyView(PlayerVolumeButton()) : nil,
                showsExtras: CompactPlayerRowContent.extrasShown(
                    hovered: isHovering,
                    popoverOpen: vm.isMediaOutputPopoverActive
                ),
                next: showsNext ? AnyView(NextEventsCard(limit: NextEvents.compactLimit, style: .lines)) : nil
            )
        }
        .onHover { isHovering = $0 }
    }
}

/// The row drawn from plain values.
struct CompactPlayerRowContent: View {
    let artwork: NSImage
    let title: String
    let artist: String
    /// 0…1, nil when unknown (a live stream).
    let progress: Double?
    let isPlaying: Bool
    /// The track's length in seconds, for seeking and the time shown while
    /// the line is dragged.
    var duration: TimeInterval = 0
    /// Seeks to a position in seconds; nil leaves the line for show only.
    /// The one-row player used to have no way to seek at all.
    var onSeek: ((TimeInterval) -> Void)? = nil
    /// Set while a video holds the playback controls: shown in place of the
    /// artist, with ⏮ ⏯ ⏭ and the line on hold (see `MusicOnlyHold`).
    var controlsNote: String? = nil
    var onPrevious: () -> Void = {}
    var onPlayPause: () -> Void = {}
    var onNext: () -> Void = {}
    var onOpenPlayer: () -> Void = {}
    /// The volume button (🔊, the slider in a popover); nil when the volume
    /// control is off in the music settings. The one-row player had no way
    /// to change the volume at all.
    var volumeControl: AnyView? = nil
    /// Whether the volume button shows.
    var showsExtras = true
    /// "Next" at the end of the row; nil when the calendar is off. Compact
    /// used to leave it out altogether.
    var next: AnyView? = nil

    /// Room for "Next": a time, "Tomorrow" and a short title.
    static let nextWidth: CGFloat = 210

    /// Where the line is being dragged to, 0…1; nil when it is not.
    @State private var scrubbing: Double?

    /// As in the full player: the extras show only while the pointer is over
    /// the player or their popover is open, so the row is calm otherwise.
    static func extrasShown(hovered: Bool, popoverOpen: Bool) -> Bool {
        hovered || popoverOpen
    }

    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double? {
        guard duration > 0 else { return nil }
        return min(max(elapsed / duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenPlayer) {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open player"))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typeface.bodyEmphasis)
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                if let scrubbing, let time = CompactSeek.timeLabel(fraction: scrubbing, duration: duration) {
                    // The artist makes way for the time while the line is dragged.
                    Text(time)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                } else if let controlsNote {
                    Text(controlsNote)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                } else if !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
                if let progress {
                    CompactSeekBar(
                        progress: progress,
                        duration: duration,
                        onSeek: controlsNote == nil ? onSeek : nil,
                        scrubbing: $scrubbing
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if let volumeControl {
                    // Hidden rather than removed, so ⏮ ⏯ ⏭ stay put.
                    volumeControl
                        .opacity(showsExtras ? 1 : 0)
                        .allowsHitTesting(showsExtras)
                        .animation(DS.hover, value: showsExtras)
                }
                HStack(spacing: 4) {
                    DSIconButton(symbol: "backward.fill", label: String(localized: "Previous Track"), action: onPrevious)
                    Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(DS.Palette.text))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(isPlaying ? "Pause" : "Play"))
                    DSIconButton(symbol: "forward.fill", label: String(localized: "Next Track"), action: onNext)
                }
                .disabled(controlsNote != nil)
                .opacity(controlsNote == nil ? 1 : DS.heldControlsOpacity)
                .animation(DS.hover, value: controlsNote == nil)
            }

            if let next {
                Rectangle()
                    .fill(DS.Palette.separator)
                    .frame(width: 1, height: 40)
                next
                    .frame(width: Self.nextWidth, height: 56)
            }
        }
        .frame(height: 56)
    }
}

/// The arithmetic of the compact player's seek line, kept apart from the
/// view so it can be tested.
enum CompactSeek {
    /// How long the line keeps showing where it was dropped while the player
    /// catches up. Players report the new position a moment after a seek, and
    /// without the hold the line jumped back and then forward again.
    static let holdLimit: TimeInterval = 2.5
    /// Close enough to the dropped point to count as arrived.
    static let arrivalTolerance = 0.02
    /// The line is 3 points, but takes clicks within this height: a click
    /// had to land right on it.
    static let hitHeight: CGFloat = 18
    static let restingThickness: CGFloat = 3
    /// Under the pointer the line thickens, so it reads as something to
    /// drag before it is grabbed.
    static let engagedThickness: CGFloat = 6

    /// The share of the track under the pointer.
    static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    /// The position to seek to, in seconds; nil when the track has no length
    /// a seek could land in (a live stream, or a sentinel from the sender).
    static func position(fraction: Double, duration: TimeInterval) -> TimeInterval? {
        guard duration.isFinite, duration > 0, duration <= 24 * 60 * 60 else { return nil }
        return min(max(fraction, 0), 1) * duration
    }

    /// Whether the line can stop holding the dropped point: the player has
    /// got there, or has had long enough to.
    static func holdIsOver(reported: Double, dropped: Double, droppedAt: Date, now: Date) -> Bool {
        abs(reported - dropped) <= arrivalTolerance || now.timeIntervalSince(droppedAt) >= holdLimit
    }

    /// "1:23 / 5:59", shown in place of the artist while dragging.
    static func timeLabel(fraction: Double, duration: TimeInterval) -> String? {
        guard let position = position(fraction: fraction, duration: duration) else { return nil }
        return "\(clock(position)) / \(clock(duration))"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// The thin progress line under the title. It thickens under the pointer;
/// a click or a drag seeks.
private struct CompactSeekBar: View {
    let progress: Double
    let duration: TimeInterval
    let onSeek: ((TimeInterval) -> Void)?
    @Binding var scrubbing: Double?

    @State private var isHovering = false
    /// Where the line was dropped and when, held until the player catches up.
    @State private var dropped: (fraction: Double, at: Date)?

    private var canSeek: Bool {
        onSeek != nil && CompactSeek.position(fraction: 0, duration: duration) != nil
    }

    private var shown: Double {
        if let scrubbing { return scrubbing }
        if let dropped { return dropped.fraction }
        return progress
    }

    private var engaged: Bool { canSeek && (isHovering || scrubbing != nil) }

    var body: some View {
        GeometryReader { geo in
            let thickness = engaged ? CompactSeek.engagedThickness : CompactSeek.restingThickness
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.Palette.raised)
                Capsule()
                    .fill(DS.Palette.text)
                    .frame(width: geo.size.width * shown)
            }
            .frame(height: thickness)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .highPriorityGesture(seekGesture(width: geo.size.width), including: canSeek ? .all : .subviews)
            .animation(DS.hover, value: engaged)
        }
        .frame(height: CompactSeek.hitHeight)
        .onHover { isHovering = $0 }
        .onChange(of: progress) { _, reported in
            guard let held = dropped else { return }
            if CompactSeek.holdIsOver(reported: reported, dropped: held.fraction, droppedAt: held.at, now: Date()) {
                dropped = nil
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Playback position"))
        .accessibilityValue(Text(CompactSeek.timeLabel(fraction: shown, duration: duration) ?? ""))
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                scrubbing = CompactSeek.fraction(atX: gesture.location.x, width: width)
            }
            .onEnded { gesture in
                let fraction = CompactSeek.fraction(atX: gesture.location.x, width: width)
                scrubbing = nil
                guard let onSeek, let position = CompactSeek.position(fraction: fraction, duration: duration) else { return }
                let droppedAt = Date()
                dropped = (fraction, droppedAt)
                onSeek(position)
                // A paused player that never reports back must not leave the
                // line stuck where it was dropped.
                DispatchQueue.main.asyncAfter(deadline: .now() + CompactSeek.holdLimit) {
                    if dropped?.at == droppedAt { dropped = nil }
                }
            }
    }
}
