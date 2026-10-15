// Skerry — a fork of Atoll (DynamicIsland)
// Copyright (C) 2026 amidamaru940 and Skerry contributors
// Licensed under the GNU General Public License v3.0 or later; see LICENSE.
//
// Renders a Skerry app icon (1024x1024, transparent margins on the macOS grid).
// Usage: swift scripts/make_skerry_icon.swift <out.png> <a|b|c> [--dev]
// The app uses "a"; --dev adds the amber DEV badge of the Debug build.

import AppKit
import CoreGraphics
import CoreText

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "icon.png"
let variant = args.count > 2 ? args[2] : "a"
let isDev = args.contains("--dev")

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}
func capsule(_ r: CGRect) -> CGPath { CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil) }

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

func drawBody(_ stops: [(CGFloat, CGColor)]) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.45))
    ctx.addPath(bodyPath); ctx.setFillColor(stops.last!.1); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
    ctx.restoreGState()
}

func drawEdge(_ alpha: CGFloat) {
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.setStrokeColor(rgb(0xFFFFFF, alpha)); ctx.setLineWidth(3); ctx.strokePath()
    ctx.restoreGState()
}

/// The island: a black capsule with a faint rim and a camera dot.
func drawIsland(_ r: CGRect, shadow: Bool = true) {
    ctx.saveGState()
    if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0x000000, 0.55)) }
    ctx.addPath(capsule(r)); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(capsule(r)); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0x2A2B30)), (0.18, rgb(0x050506)), (1, rgb(0x000000))]),
                           start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX, y: r.minY), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(capsule(r.insetBy(dx: 1, dy: 1))); ctx.setStrokeColor(rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(2); ctx.strokePath()
    let d = r.height * 0.34
    let cam = CGRect(x: r.maxX - r.height * 0.5 - d / 2, y: r.midY - d / 2, width: d, height: d)
    ctx.addEllipse(in: cam); ctx.clip()
    ctx.drawRadialGradient(gradient([(0, rgb(0x3B4C8C)), (0.45, rgb(0x141A33)), (1, rgb(0x07080D))]),
                           startCenter: CGPoint(x: cam.midX - d * 0.15, y: cam.midY + d * 0.15), startRadius: 0,
                           endCenter: CGPoint(x: cam.midX, y: cam.midY), endRadius: d / 2, options: [])
    ctx.restoreGState()
}

/// A screenshot card: rounded, with a little picture on it.
func drawCard(center: CGPoint, size s: CGSize, angle: CGFloat, fill: [(CGFloat, CGColor)], picture: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let r = CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height)
    let p = CGPath(roundedRect: r, cornerWidth: 34, cornerHeight: 34, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.45))
    ctx.addPath(p); ctx.setFillColor(fill.last!.1); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(p); ctx.clip()
    ctx.drawLinearGradient(gradient(fill), start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
    if picture {
        // Sky, sun and a low island: the screenshot's own little scene.
        let inner = r.insetBy(dx: 26, dy: 26)
        let ip = CGPath(roundedRect: inner, cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.addPath(ip); ctx.clip()
        ctx.drawLinearGradient(gradient([(0, rgb(0x5AC8FA)), (1, rgb(0x0A84FF))]),
                               start: CGPoint(x: 0, y: inner.maxY), end: CGPoint(x: 0, y: inner.minY), options: [])
        ctx.setFillColor(rgb(0xFFFFFF, 0.92))
        ctx.fillEllipse(in: CGRect(x: inner.maxX - 92, y: inner.maxY - 88, width: 46, height: 46))
        let hill = CGMutablePath()
        hill.move(to: CGPoint(x: inner.minX, y: inner.minY))
        hill.addLine(to: CGPoint(x: inner.minX, y: inner.minY + 40))
        hill.addCurve(to: CGPoint(x: inner.midX + 20, y: inner.minY + 70),
                      control1: CGPoint(x: inner.minX + 70, y: inner.minY + 110), control2: CGPoint(x: inner.midX - 40, y: inner.minY + 100))
        hill.addCurve(to: CGPoint(x: inner.maxX, y: inner.minY + 30),
                      control1: CGPoint(x: inner.midX + 80, y: inner.minY + 45), control2: CGPoint(x: inner.maxX - 60, y: inner.minY + 40))
        hill.addLine(to: CGPoint(x: inner.maxX, y: inner.minY))
        hill.closeSubpath()
        ctx.addPath(hill); ctx.setFillColor(rgb(0x1C2733)); ctx.fillPath()
    }
    ctx.restoreGState()
    ctx.restoreGState()
}

switch variant {
case "b":
    // Skerry: a low rock on the sea, the island floating above it.
    drawBody([(0, rgb(0x9BD3FF)), (0.52, rgb(0x3D8BEA)), (0.53, rgb(0x0E4C9A)), (1, rgb(0x062B5C))])
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let horizon: CGFloat = body.minY + body.height * 0.47
    let rock = CGMutablePath()
    rock.move(to: CGPoint(x: 250, y: horizon - 6))
    rock.addCurve(to: CGPoint(x: 470, y: horizon + 120), control1: CGPoint(x: 300, y: horizon + 70), control2: CGPoint(x: 380, y: horizon + 118))
    rock.addCurve(to: CGPoint(x: 640, y: horizon + 70), control1: CGPoint(x: 545, y: horizon + 122), control2: CGPoint(x: 590, y: horizon + 98))
    rock.addCurve(to: CGPoint(x: 790, y: horizon - 6), control1: CGPoint(x: 700, y: horizon + 40), control2: CGPoint(x: 750, y: horizon + 14))
    rock.closeSubpath()
    ctx.addPath(rock); ctx.setFillColor(rgb(0x14202E)); ctx.fillPath()
    ctx.addPath(rock); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0x3A4D63)), (0.5, rgb(0x14202E))]),
                           start: CGPoint(x: 470, y: horizon + 122), end: CGPoint(x: 470, y: horizon), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    for i in 0..<3 {
        let y = horizon - 70 - CGFloat(i) * 70
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.16 - CGFloat(i) * 0.04)); ctx.setLineWidth(6); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 330 + CGFloat(i) * 40, y: y)); ctx.addLine(to: CGPoint(x: 694 - CGFloat(i) * 40, y: y)); ctx.strokePath()
    }
    ctx.restoreGState()
    drawIsland(CGRect(x: 312, y: 700, width: 400, height: 118))
    drawEdge(0.18)
case "c":
    // Monogram: a white S under the island.
    drawBody([(0, rgb(0x2C2C30)), (1, rgb(0x050506))])
    drawIsland(CGRect(x: 357, y: 760, width: 310, height: 92), shadow: false)
    let font = CTFontCreateWithFontDescriptor(
        (NSFont.systemFont(ofSize: 520, weight: .heavy).fontDescriptor.withDesign(.rounded) ?? NSFont.systemFont(ofSize: 520, weight: .heavy).fontDescriptor) as CTFontDescriptor, 520, nil)
    let attr = NSAttributedString(string: "S", attributes: [.font: font, .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(attr)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    let origin = CGPoint(x: 512 - bounds.midX, y: 395 - bounds.midY)
    // Clip to the glyph, fill it with a soft white-to-silver gradient.
    if let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first {
        var glyph = CGGlyph(); CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
        if let gp = CTFontCreatePathForGlyph(font, glyph, nil) {
            var t = CGAffineTransform(translationX: origin.x, y: origin.y)
            if let path = gp.copy(using: &t) {
                ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.6))
                ctx.addPath(path); ctx.setFillColor(rgb(0xF5F5F7)); ctx.fillPath()
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                ctx.addPath(path); ctx.clip()
                ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF)), (1, rgb(0xC9CDD4))]),
                                       start: CGPoint(x: 512, y: 680), end: CGPoint(x: 512, y: 150), options: [])
            }
        }
    }
    ctx.restoreGState()
    drawEdge(0.12)
default:
    // Batch: three screenshots fanning out of the island.
    drawBody([(0, rgb(0x34363C)), (1, rgb(0x0E0F11))])
    drawIsland(CGRect(x: 287, y: 724, width: 450, height: 128))
    drawCard(center: CGPoint(x: 470, y: 430), size: CGSize(width: 400, height: 280), angle: 9,
             fill: [(0, rgb(0x5B616B)), (1, rgb(0x3A3E45))], picture: false)
    drawCard(center: CGPoint(x: 552, y: 418), size: CGSize(width: 400, height: 280), angle: -6,
             fill: [(0, rgb(0x8A919C)), (1, rgb(0x5F6670))], picture: false)
    drawCard(center: CGPoint(x: 512, y: 382), size: CGSize(width: 420, height: 294), angle: 0,
             fill: [(0, rgb(0xFFFFFF)), (1, rgb(0xDADDE2))], picture: true)
    drawEdge(0.12)
}

if isDev {
    // Debug build: an amber capsule at the bottom, so the two never mix in the Dock.
    let badge = CGRect(x: 352, y: 150, width: 320, height: 104)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0x000000, 0.5))
    ctx.addPath(capsule(badge)); ctx.setFillColor(rgb(0xFF9F0A)); ctx.fillPath()
    ctx.restoreGState()
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 68, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "DEV", attributes: [.font: font, .foregroundColor: NSColor.black]))
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: badge.midX - b.midX, y: badge.midY - b.midY)
    CTLineDraw(line, ctx)
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
