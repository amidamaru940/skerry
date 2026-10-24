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

/// The closed wing in E (docs/design/VISUAL-E.md §2.1): content 20 tall,
/// 8 from the wall and 6 from the camera. The island pads its closed content
/// by its bottom radius (14), so wing content laid out inside that padding
/// moves `outset` toward the wall.
enum ClosedWingE {
    static let content: CGFloat = 20
    static let wallInset: CGFloat = 8

    /// The closed island's own horizontal padding: its bottom radius.
    static var islandPadding: CGFloat { cornerRadiusInsets.closed.bottom }

    /// How far wing content moves from the padding to 8 from the wall. The
    /// wall starts `closed.top` in from the frame (NotchShape's top flare), so
    /// the padding already leaves the content that far from it.
    static var outset: CGFloat { max(0, islandPadding - wallInset - cornerRadiusInsets.closed.top) }

    /// The camera inside the closed notch frame, which is 4 wider.
    static func cameraWidth(closedNotchWidth: CGFloat) -> CGFloat {
        max(0, closedNotchWidth - 4)
    }

    /// Closed text is one line up to 150, cut there with a 10 pt fade (§2.1).
    static let textCap: CGFloat = 150
    static let textFade: CGFloat = 10

    /// `value` 13/600 with tabular digits, the closed wing's text.
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    /// A string's width in `font`, rounded up.
    static func measure(_ text: String, font: NSFont = valueFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// A closed state's row as numbers, in points from the camera's centre:
/// `[leading wing][middle][trailing wing]`. The island centres the row on the
/// camera and pads both sides alike, so with equal wings the black middle
/// sits on the camera and each wing starts past its edge. Content sits flush
/// to the wall: `leadingContent` and `trailingContent` are how far it reaches
/// from the wall toward the camera, wall-side padding included. Pure, so a
/// test can hold every closed state with text to "nothing hides behind the
/// camera" (E §2.1).
struct ClosedWingGeometry: Equatable {
    var leadingWing: CGFloat
    var middle: CGFloat
    var trailingWing: CGFloat
    var leadingContent: CGFloat
    var trailingContent: CGFloat
    var camera: CGFloat

    /// E: both wings as wide as the wider content, the middle the notch.
    static func equalWings(
        closedNotchWidth: CGFloat,
        middle: CGFloat? = nil,
        leading: CGFloat,
        trailing: CGFloat
    ) -> ClosedWingGeometry {
        let wing = max(0, leading, trailing)
        return ClosedWingGeometry(
            leadingWing: wing,
            middle: middle ?? closedNotchWidth,
            trailingWing: wing,
            leadingContent: leading,
            trailingContent: trailing,
            camera: ClosedWingE.cameraWidth(closedNotchWidth: closedNotchWidth)
        )
    }

    var wing: CGFloat { max(leadingWing, trailingWing) }
    var width: CGFloat { leadingWing + middle + trailingWing }
    var cameraMinX: CGFloat { -camera / 2 }
    var cameraMaxX: CGFloat { camera / 2 }
    /// The camera-side edge of the leading content.
    var leadingContentMaxX: CGFloat { -width / 2 + leadingContent }
    /// The camera-side edge of the trailing content.
    var trailingContentMinX: CGFloat { width / 2 - trailingContent }
    /// Nothing of either wing's content is inside the camera band.
    var clearsCamera: Bool {
        (leadingContent <= 0 || leadingContentMaxX <= cameraMinX)
            && (trailingContent <= 0 || trailingContentMinX >= cameraMaxX)
    }
}

/// One line of closed text (E §2.1): as wide as it is up to
/// `ClosedWingE.textCap`; longer text is cut there with a 10 pt fade at its
/// far end. Never «…», never scrolling. `width` is the text's measured width.
struct ClosedWingText: View {
    let text: String
    let width: CGFloat
    var style: DSE.TextStyle = .value
    /// A state still drawn in its own type, instead of `style`.
    var font: Font? = nil
    var color: Color = DSE.Palette.text

    var body: some View {
        let fades = width > ClosedWingE.textCap
        Group {
            if let font {
                Text(verbatim: text).font(font)
            } else {
                Text(verbatim: text).eText(style)
            }
        }
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .frame(width: min(width, ClosedWingE.textCap), alignment: .leading)
            .clipped()
            .mask {
                if fades {
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: ClosedWingE.textFade)
                    }
                } else {
                    Rectangle()
                }
            }
    }
}

/// L1 + L2 under a closed state: put it in the state's
/// `.background(alignment: .bottom)`. It reaches over the island's padding to
/// the walls, where the island's clip ends it inside the corner; the camera
/// and 6 pt either side of it stay black.
struct ClosedStateLight: View {
    var color: Color
    var strength: Double = 1
    var wings: ClosedEdgeLight.Wings = .both
    /// `vm.closedNotchSize.width`.
    var closedNotchWidth: CGFloat

    var body: some View {
        ClosedEdgeLight(
            color: color,
            strength: strength,
            wings: wings,
            cameraWidth: ClosedWingE.cameraWidth(closedNotchWidth: closedNotchWidth)
        )
        .padding(.horizontal, -ClosedWingE.islandPadding)
    }
}

// MARK: - Music

extension MusicManager {
    /// A real cover: not the launch stand-in, and not the source's app icon
    /// put in its place. The closed wing and the open player both ask this,
    /// so the cover's flight and its light never mix the two.
    var showsRealArtwork: Bool {
        albumArt !== defaultImage && !usingAppIconForArtwork
    }
}

/// The cover's light under both wings while music shows (§1.2): worked out
/// once per cover, off the main thread; 35 % while paused. No cover: the
/// neutral light.
struct ClosedMusicLight: View {
    let art: NSImage
    let hasArt: Bool
    let isPlaying: Bool
    let closedNotchWidth: CGFloat

    @State private var light: UInt32

    /// The last cover's light, so the wing that comes back after a HUD does
    /// not start neutral for a frame before its own colour arrives.
    private static weak var lastArt: NSImage?
    private static var lastLight: UInt32 = LightColor.neutral

    private struct Source: Equatable {
        let art: NSImage
        let hasArt: Bool
    }

    init(art: NSImage, hasArt: Bool, isPlaying: Bool, closedNotchWidth: CGFloat) {
        self.art = art
        self.hasArt = hasArt
        self.isPlaying = isPlaying
        self.closedNotchWidth = closedNotchWidth
        let known = hasArt && Self.lastArt === art
        _light = State(initialValue: known ? Self.lastLight : LightColor.neutral)
    }

    var body: some View {
        ClosedStateLight(
            color: LightColor.color(light),
            strength: isPlaying ? 1 : DSE.Opacity.pausedLight,
            closedNotchWidth: closedNotchWidth
        )
        .animation(.easeOut(duration: 0.2), value: isPlaying)
        .animation(.easeOut(duration: 0.2), value: light)
        .task(id: Source(art: art, hasArt: hasArt)) {
            guard hasArt else {
                light = LightColor.neutral
                return
            }
            let value = await LightColor.light(of: art)
            guard !Task.isCancelled else { return }
            Self.lastArt = art
            Self.lastLight = value
            light = value
        }
    }
}

/// The 20 pt wing art (§2.1): radius 6, no rim, 0.6 while paused. No cover:
/// the placeholder square with a note.
struct ClosedMusicArt: View {
    let art: NSImage
    let hasArt: Bool
    let isPlaying: Bool
    var side: CGFloat = ClosedWingE.content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DSE.Radius.artClosed, style: .continuous)
        Group {
            if hasArt {
                Image(nsImage: art)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                shape
                    .fill(DSE.Palette.placeholder)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DSE.Palette.tertiary(contrast))
                    )
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .opacity(isPlaying ? 1 : DSE.Opacity.dimmed)
        .animation(.easeOut(duration: 0.2), value: isPlaying)
    }
}

/// The closed music wave (§2.1): four 2 pt bars 2 apart in an 18 pt box,
/// white, at their resting heights 8/14/18/10. Static, so it costs nothing
/// while it shows. Paused: `pause.fill` 11 in its place.
struct ClosedMusicWave: View {
    let isPlaying: Bool

    static let barHeights: [CGFloat] = [8, 14, 18, 10]
    static let width: CGFloat = 14
    static let height: CGFloat = 18

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if isPlaying {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Self.barHeights.indices, id: \.self) { index in
                        Capsule()
                            .fill(DSE.Palette.text)
                            .frame(width: 2, height: Self.barHeights[index])
                    }
                }
                .transition(.opacity)
            } else {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSE.Palette.tertiary(contrast))
                    .transition(.opacity)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .animation(.easeOut(duration: 0.2), value: isPlaying)
        .accessibilityHidden(true)
    }
}

// MARK: - Screenshot flash

/// A new screenshot (sheet 1.3 S17, E §3): the 32 × 20 thumbnail with a white
/// rim and glow in the leading wing, «3 скриншота» flush right in the
/// trailing one, and white light under the leading wing that comes in at
/// full strength on the shot and fades out over 1.2 s. The wings are fixed
/// from the widest count, so a burst never resizes the island.
struct ClosedScreenshotFlash: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let flash: ScreenshotShelfManager.Flash

    @State private var image: NSImage?
    @State private var light: Double = 1
    @Environment(\.colorSchemeContrast) private var contrast

    static let thumbnail = DSE.Size.thumbnail
    /// The count's label as the catalog has it («3 снимка», "3 shots").
    static func label(count: Int) -> String {
        String(localized: "\(count) shots")
    }

    /// The wing inside the island's padding: the thumbnail or the widest
    /// two-digit label, whichever is wider («99 снимков» 76.8 → 77, so the
    /// wing is 91 with the 14 of padding: the 8 to the wall plus the 6 to the
    /// camera). Measured once: `value` is 13/600 with tabular digits, so
    /// every count of one plural form has the same width.
    static let wingWidth: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        // 21, 22 and 25 cover the plural forms (one, few, many).
        let widest = [21, 22, 25, 99]
            .map { (label(count: $0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return max(thumbnail.width, widest.rounded(.up))
    }()

    /// The thumbnail flush left, the count flush right, in equal wings.
    static func closedGeometry(closedNotchWidth: CGFloat, count: Int) -> ClosedWingGeometry {
        ClosedWingGeometry(
            leadingWing: wingWidth,
            middle: closedNotchWidth,
            trailingWing: wingWidth,
            leadingContent: thumbnail.width,
            trailingContent: ClosedWingE.measure(label(count: count)),
            camera: ClosedWingE.cameraWidth(closedNotchWidth: closedNotchWidth)
        )
    }

    var body: some View {
        let wing = Self.wingWidth
        HStack(spacing: 0) {
            thumbnailView
                .frame(width: wing, alignment: .leading)
                .offset(x: -ClosedWingE.outset)

            Rectangle()
                .fill(Color.black)
                .frame(width: vm.closedNotchSize.width)

            Text(verbatim: Self.label(count: flash.count))
                .eText(.value)
                .foregroundStyle(DSE.Palette.text)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText(countsDown: false))
                .frame(width: wing, alignment: .trailing)
                .offset(x: ClosedWingE.outset)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .background(alignment: .bottom) {
            ClosedStateLight(color: .white, strength: light, wings: .leading, closedNotchWidth: vm.closedNotchSize.width)
        }
        .task(id: flash.id) {
            image = await ScreenshotThumbnails.shared.thumbnail(for: flash.url, size: CGSize(width: 64, height: 40))
        }
        .onChange(of: flash.id, initial: true) { _, _ in
            // One finite fade per shot (L6); nothing runs after it.
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) { light = 1 }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.2)) { light = 0 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("New screenshot, \(flash.count) in batch"))
    }

    private var thumbnailView: some View {
        let shape = RoundedRectangle(cornerRadius: DSE.Radius.artClosed, style: .continuous)
        return Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                shape
                    .fill(DSE.Palette.placeholder)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DSE.Palette.tertiary(contrast))
                    )
            }
        }
        .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: DSE.Line.hairline))
        .shadow(color: .white.opacity(0.55), radius: 6)
    }
}
