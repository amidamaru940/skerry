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
/// §3.10): artwork, title and artist over a thin progress line, ⏮ ⏯ ⏭,
/// the volume button while the pointer is over the row, and the next two
/// events at the end of the row.
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

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Typeface.bodyEmphasis)
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                if !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
                if let progress {
                    Capsule()
                        .fill(DS.Palette.raised)
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(DS.Palette.text)
                                    .frame(width: geo.size.width * progress, height: 3)
                            }
                        }
                        .padding(.top, 3)
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
