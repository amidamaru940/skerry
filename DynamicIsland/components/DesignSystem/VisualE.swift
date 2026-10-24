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
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Tokens

/// Visual language E «Кромка света» (docs/design/VISUAL-E.md §1): a black
/// instrument with no grey plates. Structure is hairlines, colour enters only
/// as light from content, the accent is only ever light. Every layer here is
/// static: nothing animates, samples or polls while the island is idle.
enum DSE {
    enum Palette {
        static let island = Color.black
        static let text = DS.Palette.text
        static let textSecondary = DS.Palette.textSecondary
        static let textTertiary = DS.Palette.textTertiary
        /// The one structural line (0.5 pt): under a micro-label, between
        /// columns, the «Далее» time line, menu dividers, frame rims.
        static let hairline = Color.white.opacity(0.10)
        /// The 1 pt outline of anything that floats on black without light.
        static let edge = Color.white.opacity(0.18)
        /// The catch-light on the top inside edge of every key and panel.
        static let specular = Color.white.opacity(0.12)
        /// The unfilled part of the seek, the level line and the slider.
        static let track = Color.white.opacity(0.12)
        /// Under missing art or a loading thumbnail.
        static let placeholder = Color.white.opacity(0.05)
        /// The only fill: the keyboard cursor and a highlighted menu row.
        static let cursor = Color.white.opacity(0.08)
        static let scrim = Color.black.opacity(0.60)
        /// Light only: an outline, a glow, a dot or a rim. Never paint.
        static let accent = DS.Palette.accent
        /// The light of grey, black or white content (§4.1).
        static let lightNeutral = Color(rgb: LightColor.neutral)

        // Increase Contrast (§4.8).
        static func hairline(_ contrast: ColorSchemeContrast) -> Color {
            contrast == .increased ? .white.opacity(0.24) : hairline
        }
        static func edge(_ contrast: ColorSchemeContrast) -> Color {
            contrast == .increased ? .white.opacity(0.40) : edge
        }
        static func track(_ contrast: ColorSchemeContrast) -> Color {
            contrast == .increased ? .white.opacity(0.30) : track
        }
        static func secondary(_ contrast: ColorSchemeContrast) -> Color {
            contrast == .increased ? text : textSecondary
        }
        static func tertiary(_ contrast: ColorSchemeContrast) -> Color {
            contrast == .increased ? text : textTertiary
        }
    }

    enum Line {
        static let hairline: CGFloat = 0.5
        static let edge: CGFloat = 1
    }

    enum Opacity {
        static let pressed = 0.75
        /// Paused art.
        static let dimmed = 0.6
        static let disabled = 0.35
        /// The film while «Отменить» is offered.
        static let behindUndo = 0.28
        /// The edge and cover light while paused.
        static let pausedLight = 0.35
    }

    /// All `.continuous`.
    enum Radius {
        static let closedBottom: CGFloat = 14
        static let closedFlare: CGFloat = 6
        static let openBottom: CGFloat = 26
        static let openFlare: CGFloat = 19
        /// The 20 pt wing art and the 32 × 20 thumbnail.
        static let artClosed: CGFloat = 6
        /// The 128 pt cover (26 − 16, concentric).
        static let artOpen: CGFloat = 10
        static let frame: CGFloat = 8
        static let key: CGFloat = 10
        static let panel: CGFloat = 14
        /// A highlighted row inside a panel (14 − 4).
        static let menuRow: CGFloat = 10
        static let cursor: CGFloat = 6
    }

    enum Size {
        static let cover: CGFloat = 128
        static let film = CGSize(width: 184, height: 115)
        static let filmGap: CGFloat = 9
        static let thumbnail = CGSize(width: 32, height: 20)
        static let key: CGFloat = 32
        static let keyInToast: CGFloat = 26
        static let keyIcon: CGFloat = 16
        /// The open island's content width (640 − 2 × 35).
        static let content: CGFloat = 570
        static let seekLength: CGFloat = 550
        static let levelClosed: CGFloat = 48
        static let levelOpen: CGFloat = 60
        static let levelSound: CGFloat = 224
        /// Every seek, level and slider line; 4 under the pointer.
        static let line: CGFloat = 2
        static let lineEngaged: CGFloat = 4
        static let edgeGlow: CGFloat = 10
        static let dot: CGFloat = 6
        static let rowPitch: CGFloat = 22
        static let tabGap: CGFloat = 16
        static let header: CGFloat = 32
    }

    enum Typeface {
        static let hero = Font.system(size: 22, weight: .semibold)
        static let heroDigits = Font.system(size: 40, weight: .semibold).monospacedDigit()
        static let plusN = Font.system(size: 26, weight: .semibold).monospacedDigit()
        static let title = Font.system(size: 15, weight: .semibold)
        static let bodyEmphasis = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyTabular = Font.system(size: 13).monospacedDigit()
        static let value = Font.system(size: 13, weight: .semibold).monospacedDigit()
        static let status = Font.system(size: 12, weight: .semibold).monospacedDigit()
        static let caption = Font.system(size: 11)
        static let time = Font.system(size: 11).monospacedDigit()
        static let micro = Font.system(size: 11, weight: .semibold)
        /// SF Symbols: closed glyphs, open controls, ⏯.
        static let glyphClosed = Font.system(size: 15, weight: .semibold)
        static let glyphOpen = Font.system(size: 15, weight: .medium)
        static let playPause = Font.system(size: 22, weight: .semibold)
    }

    /// A type token with its tracking and case (§1.4).
    enum TextStyle {
        case hero, heroDigits, plusN, title, bodyEmphasis, body, bodyTabular, value, status, caption, time, micro

        var font: Font {
            switch self {
            case .hero: return Typeface.hero
            case .heroDigits: return Typeface.heroDigits
            case .plusN: return Typeface.plusN
            case .title: return Typeface.title
            case .bodyEmphasis: return Typeface.bodyEmphasis
            case .body: return Typeface.body
            case .bodyTabular: return Typeface.bodyTabular
            case .value: return Typeface.value
            case .status: return Typeface.status
            case .caption: return Typeface.caption
            case .time: return Typeface.time
            case .micro: return Typeface.micro
            }
        }

        var tracking: CGFloat {
            switch self {
            case .hero: return -0.5
            case .heroDigits: return -1
            case .plusN: return -0.3
            case .micro: return 0.6
            default: return 0
            }
        }
    }

    /// The one shadow: on the open island and on panels that hang outside it.
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 4
}

extension View {
    /// Font, tracking and case of an E type token: `.eText(.hero)`.
    func eText(_ style: DSE.TextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style == .micro ? .uppercase : nil)
    }
}

// MARK: - The light colour

/// One colour per source for every light layer (VISUAL-E §1.3): the average
/// of the picture, moved into a band that reads on black and never outshines
/// the accent. Computed once per track / icon / swatch, off the main thread,
/// and cached; no light layer samples on its own.
enum LightColor {
    struct OKLCh: Equatable {
        var l: Double
        var c: Double
        var h: Double
    }

    /// `#C4C4C8`: the light of grey, black or white content.
    static let neutral: UInt32 = 0xC4C4C8
    /// A dark cover is lifted so the line keeps ≥ 5:1 on black; a pastel one
    /// is pulled down so the line is not white.
    static let lightness: ClosedRange<Double> = 0.62...0.78
    /// A dull cover gets a minimum of colour; a neon one is tamed.
    static let chroma: ClosedRange<Double> = 0.06...0.16
    /// Below this the content counts as grey.
    static let greyChroma = 0.04
    /// The picture is averaged at this size: the colour of a 600 pt cover and
    /// of its 24 pt copy are the same, the work is not.
    static let sampleSide = 24

    // MARK: Colour of a value

    /// The light for an average colour (`0xRRGGBB`, sRGB); swatches use it as is.
    static func light(fromAverage rgb: UInt32) -> UInt32 {
        let lch = oklch(rgb)
        guard lch.c >= greyChroma else { return neutral }
        return srgb(OKLCh(
            l: min(max(lch.l, lightness.lowerBound), lightness.upperBound),
            c: min(max(lch.c, chroma.lowerBound), chroma.upperBound),
            h: lch.h
        ))
    }

    static func color(_ rgb: UInt32) -> Color { Color(rgb: rgb) }

    // MARK: Colour of a picture

    /// The light of a picture, cached by the image's identity. Synchronous:
    /// call it off the main thread, or use the async form.
    static func sampledLight(of image: NSImage) -> UInt32 {
        if let hit = identityHit(image) { return hit }
        var proposed = CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide)
        let value = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
            .flatMap(averageRGB(of:))
            .map(light(fromAverage:)) ?? neutral
        identityLock.lock()
        identityCache.setObject(NSNumber(value: value), forKey: image)
        identityLock.unlock()
        return value
    }

    /// The light of a picture already worked out, without sampling: a
    /// view starts from it so it does not recolour from neutral.
    static func cachedLight(of image: NSImage) -> UInt32? {
        identityHit(image)
    }

    /// The light of a picture, worked out on a background queue. `key` (a
    /// track id, a bundle id) caches across image objects and must always
    /// mean the same picture. No picture: the neutral light.
    static func light(of image: NSImage?, key: String? = nil) async -> UInt32 {
        guard let image else { return neutral }
        if let key, let hit = keyCache.object(forKey: key as NSString) { return hit.uint32Value }
        if let hit = identityHit(image) { return hit }
        let value: UInt32 = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: sampledLight(of: image)) }
        }
        if let key { keyCache.setObject(NSNumber(value: value), forKey: key as NSString) }
        return value
    }

    /// The same, as a colour for the views.
    static func lightColor(of image: NSImage?, key: String? = nil) async -> Color {
        color(await light(of: image, key: key))
    }

    /// The average colour of a picture (`0xRRGGBB`): `CIAreaAverage` over a
    /// small copy. Transparent parts (an app icon's corners) do not count.
    /// Nil when nothing in the picture is opaque.
    static func averageRGB(of image: CGImage) -> UInt32? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGContext(
                data: nil, width: sampleSide, height: sampleSide, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
        guard let downscaled = small.makeImage() else { return nil }

        let input = CIImage(cgImage: downscaled)
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [Float](repeating: 0, count: 4)
        ciContext.render(
            output, toBitmap: &pixel, rowBytes: 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: space
        )
        // Core Image hands the average back premultiplied.
        let alpha = Double(pixel[3])
        guard alpha > 0.01 else { return nil }
        return pack(Double(pixel[0]) / alpha, Double(pixel[1]) / alpha, Double(pixel[2]) / alpha)
    }

    // MARK: OKLab

    static func oklch(_ rgb: UInt32) -> OKLCh {
        let r = linear(Double((rgb >> 16) & 0xFF) / 255)
        let g = linear(Double((rgb >> 8) & 0xFF) / 255)
        let b = linear(Double(rgb & 0xFF) / 255)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var hue = atan2(bb, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return OKLCh(l: lightness, c: (a * a + bb * bb).squareRoot(), h: hue)
    }

    /// Back to sRGB. A colour outside sRGB keeps its lightness and hue and
    /// gives up chroma until it fits.
    static func srgb(_ lch: OKLCh) -> UInt32 {
        var channels = encodedChannels(lch)
        if !inGamut(channels) {
            var low = 0.0, high = lch.c
            for _ in 0..<24 {
                let mid = (low + high) / 2
                if inGamut(encodedChannels(OKLCh(l: lch.l, c: mid, h: lch.h))) { low = mid } else { high = mid }
            }
            channels = encodedChannels(OKLCh(l: lch.l, c: low, h: lch.h))
        }
        return pack(channels.r, channels.g, channels.b)
    }

    // MARK: Private

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static let queue = DispatchQueue(label: "skerry.light-color", qos: .utility)
    private static let keyCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 64
        return cache
    }()
    /// Weak keys: an entry goes with its image, so a new image at a reused
    /// address never inherits an old colour.
    private static let identityCache = NSMapTable<NSImage, NSNumber>.weakToStrongObjects()
    private static let identityLock = NSLock()

    private static func identityHit(_ image: NSImage) -> UInt32? {
        identityLock.lock()
        defer { identityLock.unlock() }
        return identityCache.object(forKey: image)?.uint32Value
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(max(c, 0), 1 / 2.4) - 0.055
    }

    private static func encodedChannels(_ lch: OKLCh) -> (r: Double, g: Double, b: Double) {
        let radians = lch.h * .pi / 180
        let a = lch.c * cos(radians), bb = lch.c * sin(radians)
        let l = pow(lch.l + 0.3963377774 * a + 0.2158037573 * bb, 3)
        let m = pow(lch.l - 0.1055613458 * a - 0.0638541728 * bb, 3)
        let s = pow(lch.l - 0.0894841775 * a - 1.2914855480 * bb, 3)
        return (
            encoded(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            encoded(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            encoded(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        )
    }

    private static func inGamut(_ channels: (r: Double, g: Double, b: Double)) -> Bool {
        let range = -0.0005...1.0005
        return range.contains(channels.r) && range.contains(channels.g) && range.contains(channels.b)
    }

    private static func pack(_ r: Double, _ g: Double, _ b: Double) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

// MARK: - Light on the edge

/// L1 + L2: the light on the bottom edge of one wing. A 1 pt line under a
/// 10 pt glow, full at the wall and fading toward the camera. Fill the
/// wing's extent (wall → camera − 6) and clip with the island's shape, so the
/// light ends inside the corner and never runs up the wall.
struct EdgeLight: View {
    var color: Color
    /// 1 at full strength; `DSE.Opacity.pausedLight` while paused.
    var strength: Double = 1
    /// The side the camera is on: the light fades toward it.
    var cameraEdge: HorizontalEdge = .trailing

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let wall: UnitPoint = cameraEdge == .trailing ? .leading : .trailing
        let camera: UnitPoint = cameraEdge == .trailing ? .trailing : .leading
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [color.opacity(0), color.opacity(0.60)], startPoint: .top, endPoint: .bottom))
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45), .init(color: .clear, location: 1)],
                    startPoint: wall, endPoint: camera
                ))
                .frame(height: DSE.Size.edgeGlow)
            Rectangle()
                .fill(contrast == .increased
                    ? AnyShapeStyle(color)
                    : AnyShapeStyle(LinearGradient(
                        stops: [.init(color: color, location: 0), .init(color: color, location: 0.35), .init(color: color.opacity(0.12), location: 1)],
                        startPoint: wall, endPoint: camera
                    )))
                .frame(height: 1)
        }
        .opacity(strength)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The edge light of the whole closed island: overlay it at the bottom of the
/// closed shape (full width, wings + notch) before clipping with
/// `NotchShape`. The camera and 6 pt either side of it stay black.
struct ClosedEdgeLight: View {
    enum Wings { case both, leading, trailing }

    var color: Color
    var strength: Double = 1
    var wings: Wings = .both
    /// The camera's width (the notch, 185 on the 14").
    var cameraWidth: CGFloat
    var cameraClearance: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            wing(lit: wings != .trailing, cameraEdge: .trailing)
            Color.clear.frame(width: cameraWidth + 2 * cameraClearance)
            wing(lit: wings != .leading, cameraEdge: .leading)
        }
        .frame(height: DSE.Size.edgeGlow + 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func wing(lit: Bool, cameraEdge: HorizontalEdge) -> some View {
        if lit {
            EdgeLight(color: color, strength: strength, cameraEdge: cameraEdge)
        } else {
            Color.clear
        }
    }
}

/// L3: the cover's light under the open player's 128 pt cover. Put it in the
/// cover's `.background`; the island's clip keeps it inside the black.
struct CoverGlow: View {
    var color: Color
    var strength: Double = 1
    var coverSide: CGFloat = DSE.Size.cover

    var body: some View {
        let diameter = coverSide * 2.125
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: color.opacity(0.44), location: 0),
                    .init(color: color.opacity(0.16), location: 0.36),
                    .init(color: color.opacity(0), location: 0.64),
                ],
                center: .center, startRadius: 0, endRadius: diameter / 2
            ))
            .frame(width: diameter, height: diameter)
            .offset(y: 8)
            .opacity(strength)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// L8: a 6 pt dot of light («new», the current «Далее» event).
struct LitDot: View {
    var color: Color = DSE.Palette.accent

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: DSE.Size.dot, height: DSE.Size.dot)
            .shadow(color: color.opacity(0.70), radius: 2.5)
            .overlay {
                if contrast == .increased {
                    Circle().strokeBorder(DSE.Palette.text, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Lines and labels

/// The 0.5 pt structural line.
struct Hairline: View {
    var axis: Axis = .horizontal

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(DSE.Palette.hairline(contrast))
            .frame(
                width: axis == .vertical ? DSE.Line.hairline : nil,
                height: axis == .horizontal ? DSE.Line.hairline : nil
            )
            .accessibilityHidden(true)
    }
}

/// «ДАЛЕЕ», «НЕДАВНЕЕ»: 11 pt uppercase, +0.6, tertiary, 12 tall.
struct MicroLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(verbatim: text)
            .eText(.micro)
            .foregroundStyle(DSE.Palette.tertiary(contrast))
            .lineLimit(1)
            .frame(height: 12, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A section's head: the micro-label · 6 · a full-width hairline · 6.
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(title)
            Hairline()
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Surfaces that float on black

/// The catch-light along a shape's top inside edge.
struct SpecularEdge: View {
    var cornerRadius: CGFloat
    var opacity: Double = 0.12

    var body: some View {
        RoundedRectangle(cornerRadius: max(cornerRadius - 1, 0), style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [.init(color: .white.opacity(opacity), location: 0), .init(color: .clear, location: 0.5)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
            .padding(1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// L12: a black panel with an `edge` outline and a lit top (menus,
    /// popovers, the toast capsule). Menus and popovers also take the shadow.
    func panelLift(cornerRadius: CGFloat = DSE.Radius.panel, shadow: Bool = true) -> some View {
        modifier(PanelLift(cornerRadius: cornerRadius, shadow: shadow))
    }

    /// L11: a ticked film frame or a selected row: an accent rim with a glow.
    func selectionRim(_ isOn: Bool, cornerRadius: CGFloat = DSE.Radius.frame, accent: Color = DSE.Palette.accent) -> some View {
        overlay {
            if isOn {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(accent, lineWidth: 1)
                    .shadow(color: accent.opacity(0.45), radius: 4)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The 0.5 pt rim of a film frame or thumbnail; 0.25 under the pointer.
    func hairlineRim(cornerRadius: CGFloat = DSE.Radius.frame, emphasized: Bool = false) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(emphasized ? 0.25 : 0.10), lineWidth: DSE.Line.hairline)
                .allowsHitTesting(false)
        )
    }

    /// The keyboard cursor on a row: the one allowed fill, 4 pt outset.
    func cursorFill(_ isOn: Bool, cornerRadius: CGFloat = DSE.Radius.cursor) -> some View {
        background {
            if isOn {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DSE.Palette.cursor)
                    .padding(.horizontal, -4)
            }
        }
    }
}

private struct PanelLift: ViewModifier {
    let cornerRadius: CGFloat
    let shadow: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                shape
                    .fill(DSE.Palette.island)
                    .shadow(color: shadow ? DSE.Palette.scrim : .clear, radius: DSE.shadowRadius, y: DSE.shadowY)
            )
            .overlay(shape.strokeBorder(DSE.Palette.edge(contrast), lineWidth: DSE.Line.edge).allowsHitTesting(false))
            .overlay(SpecularEdge(cornerRadius: cornerRadius))
    }
}

// MARK: - Keys

/// The one lit control (§2.3, L7): a black key with an accent outline, a lit
/// top and an accent glow, the destination app's icon leading the label.
/// `Button { … } label: { Text("Вставить в Claude · 3") }.buttonStyle(PasteKeyStyle(icon: app.icon))`.
/// `isLit: false` is the same key unlit (a sent batch in «Снимки»).
struct PasteKeyStyle: ButtonStyle {
    var icon: NSImage?
    var isLit = true
    var accent: Color = DSE.Palette.accent
    var height: CGFloat = DSE.Size.key

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(
            label: configuration.label, isPressed: configuration.isPressed,
            accent: isLit ? accent : nil, icon: icon, height: height, padding: 12
        )
    }
}

/// «Отменить», «Разрешить…», «Возобновить»: black, `edge` outline, lit top,
/// white label, never a glow. 26 tall inside a toast capsule.
struct SecondaryKeyStyle: ButtonStyle {
    var height: CGFloat = DSE.Size.key

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(
            label: configuration.label, isPressed: configuration.isPressed,
            accent: nil, icon: nil, height: height, padding: 16
        )
    }
}

private struct KeyBody: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    /// Nil: an unlit key.
    let accent: Color?
    let icon: NSImage?
    let height: CGFloat
    let padding: CGFloat

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DSE.Radius.key, style: .continuous)
        HStack(spacing: 8) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: DSE.Size.keyIcon, height: DSE.Size.keyIcon)
                    .accessibilityHidden(true)
            }
            label
                .font(DSE.Typeface.bodyEmphasis)
                .foregroundStyle(DSE.Palette.text)
                .lineLimit(1)
        }
        .padding(.horizontal, padding)
        .frame(height: height)
        .modifier(KeySurface(accent: accent, isHovering: isHovering))
        .contentShape(shape)
        .opacity(isEnabled ? (isPressed ? DSE.Opacity.pressed : 1) : DSE.Opacity.disabled)
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
    }
}

/// The body of a key: black, the accent glow and outline when lit (an
/// `edge` outline when not), the lit top. Static: the glow only moves with
/// the pointer.
private struct KeySurface: ViewModifier {
    /// Nil: an unlit key.
    let accent: Color?
    let isHovering: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DSE.Radius.key, style: .continuous)
        content
            .background {
                if let accent {
                    shape
                        .fill(DSE.Palette.island)
                        .shadow(color: accent.opacity(isHovering ? 0.60 : 0.45), radius: isHovering ? 9 : 7, y: 2)
                        .shadow(color: accent.opacity(0.60), radius: 0.5)
                } else {
                    shape.fill(DSE.Palette.island)
                }
            }
            .overlay(
                shape
                    .strokeBorder(outline, lineWidth: accent != nil && contrast == .increased ? 2 : 1)
                    .allowsHitTesting(false)
            )
            .overlay(SpecularEdge(cornerRadius: DSE.Radius.key, opacity: isHovering ? 0.18 : 0.12))
    }

    private var outline: Color {
        if let accent { return accent }
        if contrast == .increased { return DSE.Palette.edge(contrast) }
        return Color.white.opacity(isHovering ? 0.28 : 0.18)
    }
}

/// The paste key with its «куда» arrow (Buffer v3, Q11): the label pastes
/// into the app named in it; the arrow, after a 1 × 16 rule, lists the
/// recent apps. Without the arrow it is `PasteKeyStyle`'s key.
struct SplitPasteKey<Label: View>: View {
    var icon: NSImage?
    var isLit = true
    var showsArrow = true
    var arrowIsOn = false
    var arrowHelp: String = ""
    let action: () -> Void
    let arrowAction: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: DSE.Size.keyIcon, height: DSE.Size.keyIcon)
                            .accessibilityHidden(true)
                    }
                    label()
                        .font(DSE.Typeface.bodyEmphasis)
                        .foregroundStyle(DSE.Palette.text)
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                .padding(.trailing, showsArrow ? 10 : 12)
                .frame(height: DSE.Size.key)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressDimStyle())
            if showsArrow {
                Rectangle()
                    .fill(DSE.Palette.edge(contrast))
                    .frame(width: 1, height: 16)
                    .accessibilityHidden(true)
                Button(action: arrowAction) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(arrowIsOn ? DSE.Palette.text : DSE.Palette.secondary(contrast))
                        .frame(width: 26, height: DSE.Size.key)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressDimStyle())
                .help(arrowHelp)
                .accessibilityLabel(Text(verbatim: arrowHelp))
            }
        }
        .modifier(KeySurface(accent: isLit ? DSE.Palette.accent : nil, isHovering: isHovering))
        .opacity(isEnabled ? 1 : DSE.Opacity.disabled)
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
    }
}

/// A bare glyph button: no disc, no fill. At rest secondary, under the
/// pointer or while on (shuffle on, its popover open) white; pressed 0.75.
struct GlyphButton: View {
    let symbol: String
    let label: String
    var font: Font = DSE.Typeface.glyphOpen
    var box: CGFloat = DS.hitTarget
    /// A fixed colour (⏯ is always `text`); nil follows hover.
    var tint: Color? = nil
    var isOn = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(font)
                .foregroundStyle(tint ?? (isOn || isHovering ? DSE.Palette.text : DSE.Palette.secondary(contrast)))
                .frame(width: box, height: box)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
        .help(label)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Pressed is 0.75; nothing else changes.
struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? DSE.Opacity.pressed : 1)
    }
}

// MARK: - Tabs as words

/// One tab in the header (§2.2).
struct WordTabItem: Identifiable {
    let id: String
    let title: String
    /// Used when the set is too long for words.
    let symbol: String
    var isSelected: Bool
    /// The lit «new» dot after the word.
    var hasNew = false
    /// «Буфер — есть новые снимки» while dotted; the title otherwise.
    var help: String? = nil
}

/// The header's tabs as words: the selected white 600, the others grey 400,
/// 16 apart, no pill. 4–5 tabs: the selected as its word, the others as
/// glyphs; 6 and more: glyphs only. The first word starts at x 0.
struct WordTabs: View {
    enum Fit { case words, selectedWord, glyphs }

    let items: [WordTabItem]
    let onSelect: (WordTabItem) -> Void

    /// Decided per tab set, never per selection.
    static func fit(forCount count: Int) -> Fit {
        switch count {
        case ...3: return .words
        case 4...5: return .selectedWord
        default: return .glyphs
        }
    }

    var body: some View {
        // The count picks the richest layout; when even that does not fit the
        // zone left of the camera (a long Russian word), the next one is used,
        // so a tab never slides under the camera where it cannot be seen.
        let fits: [Fit] = switch Self.fit(forCount: items.count) {
        case .words: [.words, .selectedWord, .glyphs]
        case .selectedWord: [.selectedWord, .glyphs]
        case .glyphs: [.glyphs]
        }
        ViewThatFits(in: .horizontal) {
            ForEach(fits, id: \.self) { row($0) }
        }
        .frame(height: DSE.Size.header)
    }

    private func row(_ fit: Fit) -> some View {
        let half = (fit == .words ? DSE.Size.tabGap : 12) / 2
        return HStack(spacing: 0) {
            ForEach(items) { item in
                WordTabButton(
                    item: item,
                    showsWord: fit == .words || (fit == .selectedWord && item.isSelected),
                    halfGap: half
                ) { onSelect(item) }
            }
        }
        .padding(.horizontal, -half)
        .fixedSize()
    }
}

private struct WordTabButton: View {
    let item: WordTabItem
    let showsWord: Bool
    let halfGap: CGFloat
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            content
                .overlay(alignment: .topTrailing) {
                    if item.hasNew && !item.isSelected {
                        // Centre 5 pt after the last glyph, 2 pt over the cap height.
                        LitDot().offset(x: 8, y: -2)
                    }
                }
                .padding(.horizontal, halfGap)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
        .help(item.help ?? item.title)
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        if showsWord {
            Text(verbatim: item.title)
                .eText(item.isSelected ? .bodyEmphasis : .body)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        } else {
            Image(systemName: item.symbol)
                .font(DSE.Typeface.glyphOpen)
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
        }
    }

    private var color: Color {
        item.isSelected || isHovering ? DSE.Palette.text : DSE.Palette.secondary(contrast)
    }
}

// MARK: - Filters as words

/// A row of filters as words (Buffer v3): 11 pt semibold capitals, +0.6,
/// the chosen one white, the others grey and lighter under the pointer; no
/// pill, no fill. 20 tall, 16 between words, the first at x 0.
struct FilterWords<ID: Hashable>: View {
    struct Item: Identifiable {
        let id: ID
        let title: String
    }

    let items: [Item]
    let selection: ID?
    let onSelect: (ID) -> Void

    static var gap: CGFloat { 16 }

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(items) { item in
                FilterWordButton(title: item.title, isSelected: item.id == selection) { onSelect(item.id) }
            }
        }
        .fixedSize()
        .frame(height: 20)
    }
}

private struct FilterWordButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .eText(.micro)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .frame(height: 20)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .padding(.horizontal, -4)
        }
        .buttonStyle(PressDimStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .help(title)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var color: Color {
        if isSelected { return DSE.Palette.text }
        if isHovering { return DSE.Palette.text.opacity(0.85) }
        return DSE.Palette.secondary(contrast)
    }
}

// MARK: - A line of steps

/// A short line of light that picks one of a few steps (the thumbnail size
/// in «Снимки»): 60 × 2, 4 under the pointer, lit up to the chosen step.
/// A click or a drag along it moves the step.
struct StepLine: View {
    let steps: Int
    /// 0 ..< steps.
    let selected: Int
    var length: CGFloat = DSE.Size.levelOpen
    let label: String
    let onSelect: (Int) -> Void

    @State private var isHovering = false

    /// The step at `x` along a line `length` long.
    static func step(atX x: CGFloat, length: CGFloat, steps: Int) -> Int {
        guard steps > 1, length > 0 else { return 0 }
        let fraction = min(max(x / length, 0), 1)
        return Int((fraction * CGFloat(steps - 1)).rounded())
    }

    var body: some View {
        let share = steps > 1 ? Double(min(max(selected, 0), steps - 1)) / Double(steps - 1) : 1
        LevelLine(level: max(share, 0.08), length: length, isEngaged: isHovering)
            .frame(width: length, height: DS.hitTarget)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let step = Self.step(atX: value.location.x, length: length, steps: steps)
                        if step != selected { onSelect(step) }
                    }
            )
            .onHover { isHovering = $0 }
            .help(label)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(Text(verbatim: "\(selected + 1) / \(steps)"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if selected < steps - 1 { onSelect(selected + 1) }
                case .decrement: if selected > 0 { onSelect(selected - 1) }
                @unknown default: break
                }
            }
    }
}

// MARK: - Notice row

/// One line that says what is going on (paused, empty, no access): a glyph,
/// the title 13/600, the explanation in grey, and at most one key on the
/// right. No plate, no frame.
struct NoticeRow: View {
    let symbol: String
    var tint: Color = DSE.Palette.textTertiary
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// Centred, without a key: the empty states.
    var centered = false

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            if centered { Spacer(minLength: 0) }
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 15)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .eText(.bodyEmphasis)
                .foregroundStyle(DSE.Palette.text)
                .lineLimit(1)
                .fixedSize()
            if let message {
                Text(verbatim: message)
                    .font(.system(size: 12))
                    .foregroundStyle(DSE.Palette.secondary(contrast))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(message)
            }
            Spacer(minLength: centered ? 0 : 8)
            if let actionTitle, let action {
                Button(action: action) { Text(verbatim: actionTitle) }
                    .buttonStyle(SecondaryKeyStyle(height: DSE.Size.keyInToast))
                    .fixedSize()
            }
        }
        .frame(height: DSE.Size.key)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Seek along the edge

/// The seek is the island's bottom edge (§2.4, L4): a 2 pt track, the played
/// part white and glowing, 4 pt under the pointer; elapsed «1:23» and
/// remaining «−2:22» in the corners above it. Overlay it at the bottom of the
/// open island's content column (570 wide); the track is inset 10 each side
/// (550 long) and the hit strip reaches 4 pt below the edge. It draws what it
/// is given: the 1 Hz tick belongs to the caller, only while open and playing.
struct SeekEdge: View {
    /// The share played, 0…1.
    let progress: Double
    let duration: TimeInterval
    /// False while the system holds the controls: 0.35, no hit testing.
    var isEnabled = true
    /// A live stream: no track, this label centred between two rules.
    var liveLabel: String? = nil
    var trackInset: CGFloat = (DSE.Size.content - DSE.Size.seekLength) / 2
    let onSeek: ((TimeInterval) -> Void)?

    @State private var isHovering = false
    @State private var scrubbing: Double?
    /// Where the line was dropped and when, held until the player catches up.
    @State private var dropped: (fraction: Double, at: Date)?
    @Environment(\.colorSchemeContrast) private var contrast

    static let height: CGFloat = 24
    private static let hitHeight: CGFloat = 12
    private static let hitBelow: CGFloat = 4

    private var hasLength: Bool { CompactSeek.position(fraction: 0, duration: duration) != nil }
    private var canSeek: Bool { isEnabled && onSeek != nil && hasLength && liveLabel == nil }
    private var engaged: Bool { canSeek && (isHovering || scrubbing != nil) }

    private var shown: Double {
        if let scrubbing { return scrubbing }
        if let dropped { return dropped.fraction }
        return min(max(progress, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            times
                .frame(height: 13)
            Spacer(minLength: 0)
            track
                .frame(height: DSE.Size.lineEngaged, alignment: .bottom)
                .padding(.horizontal, trackInset)
        }
        .frame(height: Self.height)
        .overlay(alignment: .bottom) { hitStrip }
        .opacity(isEnabled ? 1 : DSE.Opacity.disabled)
        .onChange(of: progress) { _, reported in
            guard let held = dropped else { return }
            if CompactSeek.holdIsOver(reported: reported, dropped: held.fraction, droppedAt: held.at, now: Date()) {
                dropped = nil
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Playback position"))
        .accessibilityValue(Text(verbatim: liveLabel ?? CompactSeek.timeLabel(fraction: shown, duration: duration) ?? ""))
    }

    @ViewBuilder
    private var times: some View {
        if let liveLabel {
            Text(verbatim: liveLabel)
                .eText(.time)
                .foregroundStyle(DSE.Palette.tertiary(contrast))
                .frame(maxWidth: .infinity)
        } else if hasLength {
            let elapsed = (shown * duration).rounded(.down)
            HStack(spacing: 0) {
                Text(verbatim: CompactSeek.clock(elapsed))
                Spacer(minLength: 8)
                Text(verbatim: "\u{2212}" + CompactSeek.clock(max(duration - elapsed, 0)))
            }
            .eText(.time)
            .foregroundStyle(DSE.Palette.tertiary(contrast))
        }
    }

    @ViewBuilder
    private var track: some View {
        let thickness = engaged ? DSE.Size.lineEngaged : DSE.Size.line
        if let liveLabel {
            HStack(spacing: 8) {
                Capsule().fill(DSE.Palette.track(contrast)).frame(height: DSE.Size.line)
                Text(verbatim: liveLabel).eText(.time).hidden().frame(height: DSE.Size.line)
                Capsule().fill(DSE.Palette.track(contrast)).frame(height: DSE.Size.line)
            }
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DSE.Palette.track(contrast))
                    if hasLength {
                        Capsule()
                            .fill(DSE.Palette.text)
                            .frame(width: geo.size.width * shown)
                            .shadow(color: .white.opacity(0.55), radius: 4)
                            .shadow(color: .white.opacity(0.9), radius: 0.5)
                    }
                }
                .frame(height: thickness)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .animation(DS.hover, value: engaged)
        }
    }

    /// 8 pt inside the edge and 4 below it, along the track.
    private var hitStrip: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(seekGesture(width: geo.size.width))
        }
        .frame(height: Self.hitHeight)
        .onHover { isHovering = $0 }
        .padding(.horizontal, trackInset)
        .offset(y: Self.hitBelow)
        .allowsHitTesting(canSeek)
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

// MARK: - Level line

/// Volume, brightness, backlight as a line of light (§2.10, L5): 48 closed,
/// 60 in the open header, 224 in «Звук». Muted: the track alone.
struct LevelLine: View {
    /// 0…1.
    let level: Double
    var length: CGFloat = DSE.Size.levelClosed
    var isMuted = false
    /// 4 pt under the pointer (the «Звук» slider).
    var isEngaged = false

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let share = min(max(level, 0), 1)
        ZStack(alignment: .leading) {
            Capsule().fill(DSE.Palette.track(contrast))
            if !isMuted && share > 0 {
                Capsule()
                    .fill(DSE.Palette.text)
                    .frame(width: length * share)
                    .shadow(color: .white.opacity(0.60), radius: 3)
            }
        }
        .frame(width: length, height: isEngaged ? DSE.Size.lineEngaged : DSE.Size.line)
        .animation(DS.hover, value: isEngaged)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: isMuted ? "0 %" : share.formatted(.percent.precision(.fractionLength(0)))))
    }
}

// MARK: - «Далее»: a line of time

/// A «Далее» column (§2.6): a vertical hairline on its leading edge, the
/// micro-label and the rows 12 to its right; the rows' dots sit on the line.
/// `TimeLineColumn(label: "Далее") { TimeLineRow(…) … }`, 240 wide.
struct TimeLineColumn<Content: View>: View {
    var label: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                MicroLabel(label).padding(.bottom, 8)
            }
            content()
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) { Hairline(axis: .vertical) }
    }
}

/// One event on the line: the dot on the hairline, the time (64 wide,
/// tabular) and the title. The current event's dot is lit and its time white.
struct TimeLineRow: View {
    let time: String
    let title: String
    var isCurrent = false
    var titleColor: Color = DSE.Palette.text
    var timeWidth: CGFloat = 64
    /// The keyboard cursor, only while the column has focus.
    var isCursor = false
    var help: String? = nil
    var action: (() -> Void)? = nil

    @State private var isHovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let row = HStack(spacing: 8) {
            Text(verbatim: time)
                .eText(.bodyTabular)
                .foregroundStyle(isCurrent || isHovering ? DSE.Palette.text : DSE.Palette.secondary(contrast))
                .lineLimit(1)
                .frame(width: timeWidth, alignment: .leading)
            Text(verbatim: title)
                .eText(.body)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: DSE.Size.rowPitch)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cursorFill(isCursor)
        .overlay(alignment: .leading) { dot.offset(x: -12 - DSE.Size.dot / 2) }
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { row }
                .buttonStyle(PressDimStyle())
                .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
                .help(help ?? "")
        } else {
            row
        }
    }

    @ViewBuilder
    private var dot: some View {
        if isCurrent {
            LitDot()
        } else {
            Circle()
                .fill(DSE.Palette.tertiary(contrast))
                .frame(width: DSE.Size.dot, height: DSE.Size.dot)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Toasts

/// A toast that takes the action row (§2.9): glyph · message where «3 снимка»
/// was, and the «Отменить» key exactly where the paste key was. 32 tall.
struct ActionRowToast: View {
    let symbol: String
    /// `text`; `attention` for a warning. Never green.
    var tint: Color = DSE.Palette.text
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(DSE.Typeface.glyphClosed)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .eText(.body)
                .foregroundStyle(DSE.Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 16)
            if let actionTitle, let action {
                Button(action: action) { Text(verbatim: actionTitle) }
                    .buttonStyle(SecondaryKeyStyle())
                    .fixedSize()
            }
        }
        .frame(height: DSE.Size.key)
        .accessibilityElement(children: .contain)
    }
}

/// The toast everywhere else (§2.9): a black capsule, 26 tall, `edge`
/// outline and lit top, no shadow; an action sits after a 1 × 14 rule.
/// At most 522 wide (430 in «Сейчас»'s title row); the message truncates.
/// A warning that says what to do next («…разрешите Универсальный доступ»)
/// may take two lines (`lineLimit`): the capsule then grows to fit them.
struct ToastCapsule: View {
    let symbol: String
    var tint: Color = DSE.Palette.text
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var maxWidth: CGFloat = 522
    var lineLimit = 1

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        CappedWidth(maxWidth: maxWidth) { capsule }
    }

    private var capsule: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(DSE.Typeface.glyphClosed)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
                .padding(.trailing, 8)
            Text(verbatim: message)
                .eText(.body)
                .foregroundStyle(DSE.Palette.text)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: lineLimit > 1)
            if let actionTitle, let action {
                Rectangle()
                    .fill(DSE.Palette.edge(contrast))
                    .frame(width: 1, height: 14)
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                Button(action: action) {
                    Text(verbatim: actionTitle)
                        .eText(.bodyEmphasis)
                        .foregroundStyle(DSE.Palette.text)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(height: DSE.Size.keyInToast)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressDimStyle())
                .padding(.trailing, -8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, lineLimit > 1 ? 5 : 0)
        .frame(minHeight: DSE.Size.keyInToast)
        .frame(height: lineLimit > 1 ? nil : DSE.Size.keyInToast)
        .panelLift(cornerRadius: DSE.Size.keyInToast / 2, shadow: false)
        .accessibilityElement(children: .contain)
    }
}

/// Offers its child at most `maxWidth` and is exactly as wide as the child
/// then is, so a capsule hugs a short message and truncates a long one.
private struct CappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? maxWidth, maxWidth), height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
