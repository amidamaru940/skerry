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

@testable import Atoll
import AppKit
import XCTest

/// The light on the island's edge comes from content, but always within a
/// band that reads on black and never outshines the accent key
/// (VISUAL-E §1.3, §4.1, §4.2).
final class VisualETests: XCTestCase {
    func testGreyBlackAndWhiteContentGetTheNeutralLight() {
        for grey: UInt32 in [0x000000, 0x101010, 0x1C1C1E, 0x808080, 0xFFFFFF, 0x7A6E5C] {
            XCTAssertEqual(
                LightColor.light(fromAverage: grey), LightColor.neutral,
                String(format: "#%06X has no colour to give", grey)
            )
        }
    }

    func testANeonCoverIsTamed() {
        for neon: UInt32 in [0xFF00FF, 0xFF0000, 0x00FF00, 0x00FFFF] {
            let source = LightColor.oklch(neon)
            let light = LightColor.oklch(LightColor.light(fromAverage: neon))
            let name = String(format: "#%06X", neon)
            XCTAssertLessThanOrEqual(light.c, LightColor.chroma.upperBound + 0.005, "\(name) is never louder than the accent")
            XCTAssertGreaterThanOrEqual(light.l, LightColor.lightness.lowerBound - 0.005, name)
            XCTAssertLessThanOrEqual(light.l, LightColor.lightness.upperBound + 0.005, "\(name) is not a white line")
            XCTAssertEqual(light.h, source.h, accuracy: 3, "\(name) keeps its hue")
        }
    }

    func testADarkColouredCoverIsLiftedNotGreyed() {
        let light = LightColor.oklch(LightColor.light(fromAverage: 0x1A2A4A))
        XCTAssertEqual(light.l, 0.62, accuracy: 0.005, "lifted so the line keeps 5:1 on black")
        XCTAssertEqual(light.c, 0.063, accuracy: 0.005)
        XCTAssertEqual(light.h, 263, accuracy: 3)
    }

    func testAPastelIsPulledDownAndADullCoverGetsSomeColour() {
        let pastel = LightColor.oklch(LightColor.light(fromAverage: 0xFFD0E0))
        XCTAssertEqual(pastel.l, 0.78, accuracy: 0.005)
        XCTAssertEqual(pastel.c, 0.06, accuracy: 0.005)

        let dull = LightColor.oklch(LightColor.light(fromAverage: 0x806A50))
        XCTAssertEqual(dull.l, 0.62, accuracy: 0.005)
        XCTAssertEqual(dull.c, 0.06, accuracy: 0.005)
    }

    func testAColourInsideTheBandIsKept() {
        // The Би-2 cover's light on the concept board.
        assertClose(LightColor.light(fromAverage: 0xDE8060), 0xDE8060)
    }

    func testAPictureIsAveragedOnce() {
        let cover = solidImage(0xDE8060)
        assertClose(LightColor.sampledLight(of: cover), LightColor.light(fromAverage: 0xDE8060))
        XCTAssertEqual(LightColor.sampledLight(of: cover), LightColor.sampledLight(of: cover), "the second read comes from the cache")
    }

    func testTransparentCornersDoNotDarkenAnIcon() {
        let icon = solidImage(0x2F8CE6, opaqueShare: 0.5)
        assertClose(LightColor.sampledLight(of: icon), LightColor.light(fromAverage: 0x2F8CE6))
    }

    func testATransparentPictureHasTheNeutralLight() {
        XCTAssertEqual(LightColor.sampledLight(of: solidImage(0xDE8060, opaqueShare: 0)), LightColor.neutral)
    }

    func testNoPictureMeansTheNeutralLight() async {
        let none = await LightColor.light(of: nil, key: "nothing")
        XCTAssertEqual(none, LightColor.neutral)
    }

    func testTheAsyncFormMatchesAndCachesByKey() async {
        let cover = solidImage(0x4991AB)
        let first = await LightColor.light(of: cover, key: "visual-e-test-track")
        assertClose(first, LightColor.light(fromAverage: 0x4991AB))
        let again = await LightColor.light(of: solidImage(0xFF0000), key: "visual-e-test-track")
        XCTAssertEqual(again, first, "one number per track: the key decides")
    }

    func testTabsTurnToGlyphsOnlyWhenWordsCannotFit() {
        XCTAssertEqual(WordTabs.fit(forCount: 3), .words)
        XCTAssertEqual(WordTabs.fit(forCount: 4), .selectedWord)
        XCTAssertEqual(WordTabs.fit(forCount: 5), .selectedWord)
        XCTAssertEqual(WordTabs.fit(forCount: 6), .glyphs)
    }

    // MARK: Helpers

    private func assertClose(_ lhs: UInt32, _ rhs: UInt32, tolerance: Int = 2, file: StaticString = #filePath, line: UInt = #line) {
        for shift: UInt32 in [16, 8, 0] {
            let a = Int((lhs >> shift) & 0xFF), b = Int((rhs >> shift) & 0xFF)
            XCTAssertLessThanOrEqual(
                abs(a - b), tolerance,
                String(format: "#%06X vs #%06X", lhs, rhs), file: file, line: line
            )
        }
    }

    /// A 32 pt picture of one colour; `opaqueShare` of it (from the left) is
    /// painted, the rest is transparent.
    private func solidImage(_ rgb: UInt32, opaqueShare: CGFloat = 1) -> NSImage {
        let side = 32
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        ))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(side) * opaqueShare, height: CGFloat(side)))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: side, height: side))
    }
}
