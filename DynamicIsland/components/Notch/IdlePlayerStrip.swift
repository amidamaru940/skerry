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
import SwiftUI

/// "Nothing playing": the last track greyed, with a way to resume it, above
/// "Next", instead of a full player with nothing in it (docs/PLAN-DESIGN.md
/// §3.3).
struct IdlePlayerStrip: View {
    @ObservedObject private var musicManager = MusicManager.shared

    var body: some View {
        IdlePlayerStripContent(
            artwork: musicManager.hasActiveSession ? musicManager.albumArt : nil,
            title: musicManager.hasActiveSession ? musicManager.songTitle : nil,
            artist: musicManager.artistName,
            controlsNote: musicManager.controlsNote,
            onResume: { MusicManager.shared.togglePlay() },
            onOpenPlayer: { MusicManager.shared.openMusicApp() }
        )
    }
}

/// The strip drawn from plain values. Without a last track it offers to
/// open the player.
struct IdlePlayerStripContent: View {
    let artwork: NSImage?
    let title: String?
    let artist: String
    /// While a video holds the controls ("Controls are with a video in
    /// Chrome"): «Возобновить» would reach the video, so, as in the player,
    /// it is dimmed and does nothing, and the note says why. It looked live
    /// and silently did nothing (23.10).
    var controlsNote: String? = nil
    var onResume: () -> Void = {}
    var onOpenPlayer: () -> Void = {}

    var body: some View {
        // E: no plates; the paused cover at 0.6, the 5 % square without one,
        // and a black secondary key (VISUAL-E §2.3, §2.6).
        HStack(spacing: 10) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(DSE.Opacity.dimmed)
                } else {
                    Image(systemName: "music.note")
                        .font(DSE.Typeface.glyphOpen)
                        .foregroundStyle(DSE.Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DSE.Palette.placeholder)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: DSE.Radius.artClosed, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title ?? String(localized: "Nothing playing"))
                    .eText(.body)
                    .foregroundStyle(DSE.Palette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .eText(.caption)
                    .foregroundStyle(DSE.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if title != nil {
                Button(String(localized: "Resume"), action: onResume)
                    .buttonStyle(SecondaryKeyStyle())
                    .fixedSize()
                    .disabled(controlsNote != nil)
                    .opacity(controlsNote == nil ? 1 : DS.heldControlsOpacity)
                    .animation(DS.hover, value: controlsNote == nil)
            } else {
                Button(String(localized: "Open player"), action: onOpenPlayer)
                    .buttonStyle(SecondaryKeyStyle())
                    .fixedSize()
            }
        }
        .frame(height: 36)
        .accessibilityElement(children: .contain)
    }

    var subtitle: String {
        guard title != nil else { return String(localized: "Music, podcasts and videos show up here") }
        if let controlsNote { return controlsNote }
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? String(localized: "Paused") : "\(artist) · \(String(localized: "Paused"))"
    }
}
