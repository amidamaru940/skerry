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
    var onResume: () -> Void = {}
    var onOpenPlayer: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .saturation(0)
                        .opacity(0.55)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.Palette.card)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title ?? String(localized: "Nothing playing"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DS.Typeface.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if title != nil {
                Button(action: onResume) {
                    Label(String(localized: "Resume"), systemImage: "play.fill")
                }
                .buttonStyle(DSButtonStyle(kind: .secondary, height: 28))
            } else {
                Button(String(localized: "Open player"), action: onOpenPlayer)
                    .buttonStyle(DSButtonStyle(kind: .quiet, height: 28))
            }
        }
        .frame(height: 36)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        guard title != nil else { return String(localized: "Music, podcasts and videos show up here") }
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? String(localized: "Paused") : "\(artist) · \(String(localized: "Paused"))"
    }
}
