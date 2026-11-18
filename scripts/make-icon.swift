#!/usr/bin/env swift
// Draws Glint's app icon and writes every size the macOS AppIcon set needs.
//
//   swift scripts/make-icon.swift [output-dir]
//
// Default output: App/Resources/Assets.xcassets/AppIcon.appiconset (relative to the repo root).
// The artwork is vector, so each PNG is rendered at its own pixel size rather than downscaled.
//
// Motif: a line of text with a highlighted selection and a dark floating action bar (three dots)
// above it, on an indigo-to-violet macOS-style rounded square.

import AppKit
import Foundation

// MARK: - Geometry helpers

/// macOS-style rounded square with continuous ("squircle") corners: each corner is a pair of cubic
/// curves that ease into the straight edges instead of a circular arc meeting them abruptly.
func squircle(in rect: CGRect) -> CGPath {
    let r = rect.width * 0.2237 // Apple's corner radius ratio for the 824pt icon body
    let k: CGFloat = 1.528665    // how far the smoothed corner reaches along each edge, in radii
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    let p = CGMutablePath()
    // Corner helper: from a point on one edge, around corner `c`, to a point on the next edge.
    // `u` points along the incoming edge toward the corner, `v` along the outgoing edge away from it.
    func corner(_ c: CGPoint, _ u: CGPoint, _ v: CGPoint) {
        func pt(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
            // a: distance back from the corner along the incoming edge; b: distance out along the outgoing edge.
            CGPoint(x: c.x - u.x * a * r + v.x * b * r, y: c.y - u.y * a * r + v.y * b * r)
        }
        p.addLine(to: pt(k, 0))
        p.addCurve(to: pt(0.63149399, 0.07491100), control1: pt(1.08849296, 0), control2: pt(0.86840694, 0))
        p.addCurve(to: pt(0.07491100, 0.63149399), control1: pt(0.37282383, 0.16905956), control2: pt(0.16905956, 0.37282383))
        p.addCurve(to: pt(0, k), control1: pt(0, 0.86840694), control2: pt(0, 1.08849296))
    }
    p.move(to: CGPoint(x: minX + k * r, y: maxY))
    corner(CGPoint(x: maxX, y: maxY), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: -1))  // top right
    corner(CGPoint(x: maxX, y: minY), CGPoint(x: 0, y: -1), CGPoint(x: -1, y: 0)) // bottom right
    corner(CGPoint(x: minX, y: minY), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1))  // bottom left
    corner(CGPoint(x: minX, y: maxY), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0))   // top left
    p.closeSubpath()
    return p
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linearGradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

// MARK: - Artwork (drawn in a 1024×1024 coordinate space, y up)

func drawIcon(in ctx: CGContext, pixelSize: Int) {
    let small = pixelSize <= 32 // simplify details that turn to mush at tiny sizes
    ctx.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Apple's grid: an 824×824 shape centred in the 1024 canvas, nudged up a little to leave room for the shadow.
    let body = CGRect(x: 100, y: 112, width: 824, height: 824)
    let shape = squircle(in: body)

    // Soft drop shadow under the shape.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.32))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x4338CA))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient: indigo (top left) to violet (bottom right).
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(linearGradient([color(0x5B6CFF), color(0x6D4AF0), color(0x9A3FD8)], [0, 0.55, 1]),
                           start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // Gentle light from the top for depth.
    ctx.drawRadialGradient(linearGradient([color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)], [0, 1]),
                           startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 980), endRadius: 720, options: [])
    // Thin inner highlight along the edge (dropped at tiny sizes).
    if !small {
        ctx.addPath(shape)
        ctx.setStrokeColor(color(0xFFFFFF, 0.18))
        ctx.setLineWidth(6)
        ctx.strokePath()
    }
    ctx.restoreGState()

    // --- Text lines (the "document") ---
    let lineColor = color(0xFFFFFF, small ? 0.55 : 0.42)
    let lineHeight: CGFloat = 46
    let left: CGFloat = 238
    func textLine(y: CGFloat, width: CGFloat, alpha: CGFloat? = nil) {
        ctx.addPath(roundedRect(CGRect(x: left, y: y, width: width, height: lineHeight), radius: lineHeight / 2))
        ctx.setFillColor(alpha.map { color(0xFFFFFF, $0) } ?? lineColor)
        ctx.fillPath()
    }

    // --- Selected text: a warm highlight with a darker text bar inside ---
    let selection = CGRect(x: 214, y: 360, width: 596, height: 124)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x2A0A55, 0.35))
    ctx.addPath(roundedRect(selection, radius: 20))
    ctx.setFillColor(color(0xFFC83D))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(roundedRect(selection, radius: 20))
    ctx.clip()
    ctx.drawLinearGradient(linearGradient([color(0xFFE07A), color(0xFFB627)], [0, 1]),
                           start: CGPoint(x: 0, y: selection.maxY), end: CGPoint(x: 0, y: selection.minY), options: [])
    ctx.restoreGState()
    // The selected words (left out at tiny sizes, where a solid highlight reads better).
    if !small {
        ctx.addPath(roundedRect(CGRect(x: selection.minX + 44, y: selection.midY - 25, width: 300, height: 50), radius: 25))
        ctx.addPath(roundedRect(CGRect(x: selection.minX + 372, y: selection.midY - 25, width: 180, height: 50), radius: 25))
        ctx.setFillColor(color(0x7A3E00, 0.55))
        ctx.fillPath()
    }

    if !small {
        // Selection handles at both ends.
        let handleColor = color(0xFFFFFF, 0.95)
        for (x, top) in [(selection.minX - 2, true), (selection.maxX + 2, false)] {
            ctx.setFillColor(handleColor)
            ctx.addPath(roundedRect(CGRect(x: x - 5, y: selection.minY - 8, width: 10, height: selection.height + 16), radius: 5))
            ctx.fillPath()
            let cy = top ? selection.maxY + 14 : selection.minY - 14
            ctx.fillEllipse(in: CGRect(x: x - 17, y: cy - 17, width: 34, height: 34))
        }
        // Surrounding lines of text.
        textLine(y: 264, width: 470)
        textLine(y: 188, width: 330, alpha: 0.3)
    } else {
        textLine(y: 250, width: 420)
    }

    // --- Floating action bar: dark pill with three dots and a pointer to the selection ---
    let pill = CGRect(x: 232, y: 592, width: 560, height: 196)
    let pointer = CGMutablePath()
    pointer.move(to: CGPoint(x: 512 - 46, y: pill.minY + 2))
    pointer.addLine(to: CGPoint(x: 512, y: pill.minY - 46))
    pointer.addLine(to: CGPoint(x: 512 + 46, y: pill.minY + 2))
    pointer.closeSubpath()
    let bar = CGMutablePath()
    bar.addPath(roundedRect(pill, radius: pill.height / 2))
    bar.addPath(pointer)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x12002E, 0.45))
    ctx.addPath(bar)
    ctx.setFillColor(color(0x17142B))
    ctx.fillPath()
    ctx.restoreGState()
    // Subtle top sheen on the pill.
    ctx.saveGState()
    ctx.addPath(bar)
    ctx.clip()
    ctx.drawLinearGradient(linearGradient([color(0xFFFFFF, 0.12), color(0xFFFFFF, 0)], [0, 1]),
                           start: CGPoint(x: 0, y: pill.maxY), end: CGPoint(x: 0, y: pill.midY), options: [])
    ctx.restoreGState()

    // Three "action" dots; the first is lit to suggest a hovered button.
    let dotRadius: CGFloat = small ? 34 : 30
    let spacing: CGFloat = 150
    for i in 0..<3 {
        let cx = 512 + CGFloat(i - 1) * spacing
        let cy = pill.midY
        ctx.setFillColor(i == 0 ? color(0xFFD45C) : color(0xFFFFFF, 0.92))
        ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: cy - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    }
    if !small {
        // Hairline dividers between the buttons.
        ctx.setFillColor(color(0xFFFFFF, 0.14))
        for i in 0..<2 {
            let x = 512 + (CGFloat(i) - 0.5) * spacing
            ctx.fill(CGRect(x: x - 2, y: pill.midY - 46, width: 4, height: 92))
        }
    }
}

// MARK: - Rendering

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    drawIcon(in: ctx, pixelSize: pixels)
    gc.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : repoRoot.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

struct Entry { let points: Int; let scale: Int; var pixels: Int { points * scale } }
let entries = [16, 32, 128, 256, 512].flatMap { [Entry(points: $0, scale: 1), Entry(points: $0, scale: 2)] }

var images: [[String: String]] = []
var rendered: [Int: Data] = [:]
for e in entries {
    let name = "icon_\(e.points)x\(e.points)\(e.scale == 2 ? "@2x" : "").png"
    let data = rendered[e.pixels] ?? renderPNG(pixels: e.pixels)
    rendered[e.pixels] = data
    try data.write(to: outDir.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(e.scale)x", "size": "\(e.points)x\(e.points)"])
    print("wrote \(name) (\(e.pixels)px)")
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote Contents.json → \(outDir.path)")
