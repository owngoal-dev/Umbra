#!/usr/bin/env swift
//
//  make-icon.swift
//  Umbra
//
//  Draws the Umbra app icon (a total solar eclipse: a dark umbral disk covering a
//  warm sun, leaving a thin bright crescent and corona at the upper right) and
//  writes every size listed in AppIcon.appiconset/Contents.json plus BrandIcon.
//
//  Usage: swift Tools/make-icon.swift
//
//  Output is deterministic: the artwork is pure CoreGraphics vector drawing,
//  rendered 4x supersampled and box-filtered down to each target size.
//

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Palette

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgba(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: sRGB,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ])!
}

let backgroundCore: UInt32 = 0x0E_1424  // near-black blue, canvas centre
let backgroundEdge: UInt32 = 0x0507_0D  // near-black, canvas corners
let sunWarm: UInt32 = 0xFFD2_7A  // photosphere highlight
let sunDeep: UInt32 = 0xFF7A_3D  // photosphere shadow
let coronaWarm: UInt32 = 0xFF9A_4D  // outer glow
let coronaBright: UInt32 = 0xFFD9_A0  // tight rim glow
let umbraCore: UInt32 = 0x1016_26  // occulting disk centre
let umbraEdge: UInt32 = 0x0609_11  // occulting disk edge
let rimCool: UInt32 = 0x7FB3_FF  // cool limb highlight

// MARK: - Geometry (in a 1024 x 1024 design space)

let canvas: CGFloat = 1024
let umbraCentre = CGPoint(x: 496, y: 496)
let umbraRadius: CGFloat = 356
let eclipseOffset: CGFloat = 40  // per axis; the disk sits down-left of the sun
let sunCentre = CGPoint(x: umbraCentre.x + eclipseOffset, y: umbraCentre.y + eclipseOffset)
let sunRadius: CGFloat = 352

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: sRGB,
        colors: stops.map { rgba($0.0, $0.1) } as CFArray,
        locations: stops.map { $0.2 })!
}

func circle(_ centre: CGPoint, _ radius: CGFloat) -> CGPath {
    CGPath(
        ellipseIn: CGRect(
            x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2),
        transform: nil)
}

// MARK: - Artwork

func draw(into context: CGContext) {
    let centre = CGPoint(x: canvas / 2, y: canvas / 2)

    // 1. Deep space background.
    context.drawRadialGradient(
        gradient([(backgroundCore, 1, 0), (backgroundEdge, 1, 1)]),
        startCenter: centre, startRadius: 0,
        endCenter: centre, endRadius: canvas * 0.62,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // 2. Wide corona halo, centred on the sun so it survives downscaling.
    context.drawRadialGradient(
        gradient([
            (coronaWarm, 0.60, 0), (coronaWarm, 0.30, 0.25),
            (coronaWarm, 0.09, 0.60), (coronaWarm, 0, 1),
        ]),
        startCenter: sunCentre, startRadius: sunRadius * 0.90,
        endCenter: sunCentre, endRadius: sunRadius * 1.92,
        options: [])

    // 3. Tight rim glow hugging the photosphere.
    context.drawRadialGradient(
        gradient([(coronaBright, 0.85, 0), (coronaBright, 0.35, 0.45), (coronaBright, 0, 1)]),
        startCenter: sunCentre, startRadius: sunRadius * 0.99,
        endCenter: sunCentre, endRadius: sunRadius * 1.20,
        options: [])

    // 4. The sun itself.
    context.saveGState()
    context.addPath(circle(sunCentre, sunRadius))
    context.clip()
    context.drawLinearGradient(
        gradient([(sunWarm, 1, 0), (sunDeep, 1, 1)]),
        start: CGPoint(x: sunCentre.x + sunRadius * 0.7, y: sunCentre.y + sunRadius * 0.7),
        end: CGPoint(x: sunCentre.x - sunRadius * 0.7, y: sunCentre.y - sunRadius * 0.7),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    // 5. The umbra: a slightly larger dark disk, offset down-left, so only a thin
    //    crescent of the sun and its corona stay visible at the upper right.
    context.saveGState()
    context.addPath(circle(umbraCentre, umbraRadius))
    context.clip()
    context.drawRadialGradient(
        gradient([(umbraCore, 1, 0), (umbraEdge, 1, 1)]),
        startCenter: umbraCentre, startRadius: 0,
        endCenter: umbraCentre, endRadius: umbraRadius,
        options: [.drawsAfterEndLocation])

    // 5a. Limb shading: a band that follows the disk's own edge, transparent
    //     towards the centre, attenuated by direction so the corona wraps warmly
    //     onto the limb facing the sun and a faint cool sheen lifts the far side.
    //     This keeps the disk reading as a sphere instead of a flat cut-out.
    let diagonal = umbraRadius * 0.7071
    let towardsSun = CGPoint(x: umbraCentre.x + diagonal, y: umbraCentre.y + diagonal)
    let awayFromSun = CGPoint(x: umbraCentre.x - diagonal, y: umbraCentre.y - diagonal)
    func limbBand(_ colour: UInt32, peak: CGFloat, inner: CGFloat, from: CGPoint, to: CGPoint) {
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.drawRadialGradient(
            gradient([(colour, 0, 0), (colour, peak * 0.35, 0.72), (colour, peak, 1)]),
            startCenter: umbraCentre, startRadius: umbraRadius * inner,
            endCenter: umbraCentre, endRadius: umbraRadius,
            options: [.drawsAfterEndLocation])
        context.setBlendMode(.destinationIn)
        context.drawLinearGradient(
            gradient([(0xFFFF_FF, 1, 0), (0xFFFF_FF, 0.35, 0.5), (0xFFFF_FF, 0, 1)]),
            start: from, end: to,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.endTransparencyLayer()
    }
    limbBand(coronaBright, peak: 0.55, inner: 0.70, from: towardsSun, to: awayFromSun)
    limbBand(rimCool, peak: 0.16, inner: 0.62, from: awayFromSun, to: towardsSun)
    context.restoreGState()

    // 6. A hairline cool highlight on the umbral limb, brightest on the shadow
    //    side, so the disk keeps a readable outline against the dark background.
    context.saveGState()
    context.addPath(circle(umbraCentre, umbraRadius - 1.5))
    context.setLineWidth(3)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient([(rimCool, 0.40, 0), (rimCool, 0.12, 0.55), (rimCool, 0, 1)]),
        start: CGPoint(x: umbraCentre.x - diagonal, y: umbraCentre.y - diagonal),
        end: CGPoint(x: umbraCentre.x + diagonal, y: umbraCentre.y + diagonal),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

// MARK: - Rendering

func bitmap(_ pixels: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    return context
}

/// Renders the artwork 4x supersampled, then box-filters down to `pixels`.
func render(_ pixels: Int) -> CGImage {
    let supersample = min(pixels * 4, 4096)
    let large = bitmap(supersample)
    large.scaleBy(x: CGFloat(supersample) / canvas, y: CGFloat(supersample) / canvas)
    draw(into: large)
    let source = large.makeImage()!
    guard supersample != pixels else { return source }
    let target = bitmap(pixels)
    target.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return target.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil)
    else {
        fatalError("Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot encode \(url.path)") }
}

// MARK: - Outputs

let appIconSizes: [(String, Int)] = [
    ("icon-20@2x.png", 40), ("icon-20@3x.png", 60),
    ("icon-29.png", 29), ("icon-29@2x.png", 58), ("icon-29@3x.png", 87),
    ("icon-40@2x.png", 80), ("icon-40@3x.png", 120),
    ("icon-60@2x.png", 120), ("icon-60@3x.png", 180),
    ("icon-20-ipad.png", 20), ("icon-20@2x-ipad.png", 40),
    ("icon-29-ipad.png", 29), ("icon-29@2x-ipad.png", 58),
    ("icon-40.png", 40), ("icon-76.png", 76), ("icon-76@2x.png", 152),
    ("icon-83.5@2x.png", 167), ("icon-1024.png", 1024),
]

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()  // Tools
    .deletingLastPathComponent()  // repository root
let appIcon = root.appendingPathComponent("Umbra/Assets.xcassets/AppIcon.appiconset")
let brandIcon = root.appendingPathComponent("Umbra/Assets.xcassets/BrandIcon.imageset")

var cache: [Int: CGImage] = [:]
for (name, pixels) in appIconSizes {
    let image = cache[pixels] ?? render(pixels)
    cache[pixels] = image
    write(image, to: appIcon.appendingPathComponent(name))
    print("\(name) \(pixels)x\(pixels)")
}
write(render(228), to: brandIcon.appendingPathComponent("BrandIcon.png"))
print("BrandIcon.png 228x228")
