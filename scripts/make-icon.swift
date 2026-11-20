#!/usr/bin/env swift
// Draws Glint's app icon and writes every size the macOS AppIcon set needs.
//
//   swift scripts/make-icon.swift [output-dir]
//
// Default output: App/Resources/Assets.xcassets/AppIcon.appiconset (relative to the repo root).
// The artwork is vector, so each PNG is rendered at its own pixel size rather than downscaled.
//
// Motif: a light floating action bar (three buttons, one lit amber) pointing at an amber text selection,
// on a solid charcoal macOS-style rounded square. Solid colours only; it matches the website mark.

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

// MARK: - Artwork (drawn in a 1024×1024 coordinate space, y up)
//
// The shapes mirror the website mark (site/public/favicon.svg), which is laid out on a 32×32 grid with y
// pointing down. `grid` maps a rectangle on that grid onto the 824pt icon body. Every fill is a solid colour:
// no gradients, no shadows, no purple.

let charcoal: UInt32 = 0x1C1C1E
let paper: UInt32 = 0xFAFAF9
let amber: UInt32 = 0xFFBE36
let amberDeep: UInt32 = 0xC8861D
let stone: UInt32 = 0x57534E

func drawIcon(in ctx: CGContext, pixelSize: Int) {
    let small = pixelSize <= 32 // simplify details that turn to mush at tiny sizes
    ctx.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Apple's grid: an 824×824 shape centred in the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let unit = body.width / 32
    func grid(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: body.minX + x * unit, y: body.maxY - (y + h) * unit, width: w * unit, height: h * unit)
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * unit, y: body.maxY - y * unit) }
    func fill(_ path: CGPath, _ hex: UInt32) {
        ctx.addPath(path)
        ctx.setFillColor(color(hex))
        ctx.fillPath()
    }

    // Background: a solid charcoal squircle with a hairline edge so it stays visible on a dark Dock.
    let shape = squircle(in: body)
    fill(shape, charcoal)
    if !small {
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.addPath(shape)
        ctx.setStrokeColor(color(0x3A3A3C))
        ctx.setLineWidth(8) // half of it is clipped away, leaving a 4pt inner edge
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Floating action bar: a light pill with a pointer and three buttons, the first lit amber.
    let pill = grid(6, 5.5, 20, 8)
    let bar = CGMutablePath()
    bar.addPath(roundedRect(pill, radius: pill.height / 2))
    bar.move(to: point(14, 13.3))
    bar.addLine(to: point(16, 15.6))
    bar.addLine(to: point(18, 13.3))
    bar.closeSubpath()
    fill(bar, paper)
    let dotRadius = (small ? 1.8 : 1.5) * unit
    for (i, cx) in [CGFloat(11), 16, 21].enumerated() {
        let c = point(cx, 9.5)
        ctx.setFillColor(color(i == 0 ? amber : charcoal))
        ctx.fillEllipse(in: CGRect(x: c.x - dotRadius, y: c.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    }

    // Selected text: a solid amber highlight with the selected words in a deeper amber.
    let selection = grid(6, 18, 20, 5.5)
    fill(roundedRect(selection, radius: 1.6 * unit), amber)
    if !small {
        fill(roundedRect(grid(8, 19.75, 8, 2), radius: unit), amberDeep)
        fill(roundedRect(grid(18, 19.75, 6, 2), radius: unit), amberDeep)
    }

    // The next line of unselected text.
    fill(roundedRect(grid(6, 25.5, 14, 2), radius: unit), stone)
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
