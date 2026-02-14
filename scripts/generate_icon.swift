#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: Int(size) * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Failed to create context")
    exit(1)
}

// CoreGraphics origin is bottom-left. We flip so y=0 is top.
context.translateBy(x: 0, y: size)
context.scaleBy(x: 1, y: -1)

// Background: Royal blue gradient
let gradientColors = [
    CGColor(red: 0.102, green: 0.294, blue: 0.549, alpha: 1.0),  // #1A4B8C
    CGColor(red: 0.176, green: 0.357, blue: 0.627, alpha: 1.0)   // #2D5BA0
] as CFArray

guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradientColors,
    locations: [0.0, 1.0]
) else {
    print("Failed to create gradient")
    exit(1)
}

context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: size, y: size),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// Crescent moon — draw outer circle, then use even-odd with inner circle
let moonCenter = CGPoint(x: size * 0.48, y: size * 0.42)
let moonRadius: CGFloat = size * 0.24
let cutoutOffset: CGFloat = size * 0.10

let crescentPath = CGMutablePath()

// Outer moon circle
crescentPath.addEllipse(in: CGRect(
    x: moonCenter.x - moonRadius,
    y: moonCenter.y - moonRadius,
    width: moonRadius * 2,
    height: moonRadius * 2
))

// Inner cutout circle — fully contained within outer circle
let cutoutCenter = CGPoint(x: moonCenter.x + cutoutOffset, y: moonCenter.y - cutoutOffset * 0.15)
let cutoutRadius = moonRadius * 0.75
crescentPath.addEllipse(in: CGRect(
    x: cutoutCenter.x - cutoutRadius,
    y: cutoutCenter.y - cutoutRadius,
    width: cutoutRadius * 2,
    height: cutoutRadius * 2
))

context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
context.addPath(crescentPath)
context.fillPath(using: .evenOdd)

// Star near the crescent opening
let starCenter = CGPoint(x: size * 0.66, y: size * 0.26)
let starRadius: CGFloat = size * 0.035
context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))

// Simple 4-point star
let starPath = CGMutablePath()
starPath.move(to: CGPoint(x: starCenter.x, y: starCenter.y - starRadius))
starPath.addLine(to: CGPoint(x: starCenter.x + starRadius * 0.3, y: starCenter.y - starRadius * 0.3))
starPath.addLine(to: CGPoint(x: starCenter.x + starRadius, y: starCenter.y))
starPath.addLine(to: CGPoint(x: starCenter.x + starRadius * 0.3, y: starCenter.y + starRadius * 0.3))
starPath.addLine(to: CGPoint(x: starCenter.x, y: starCenter.y + starRadius))
starPath.addLine(to: CGPoint(x: starCenter.x - starRadius * 0.3, y: starCenter.y + starRadius * 0.3))
starPath.addLine(to: CGPoint(x: starCenter.x - starRadius, y: starCenter.y))
starPath.addLine(to: CGPoint(x: starCenter.x - starRadius * 0.3, y: starCenter.y - starRadius * 0.3))
starPath.closeSubpath()
context.addPath(starPath)
context.fillPath()

// Small alarm bell at bottom center
let bellX: CGFloat = size * 0.5
let bellY: CGFloat = size * 0.76
let bellWidth: CGFloat = size * 0.13
let bellHeight: CGFloat = size * 0.11

context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.55))

// Bell body (rounded trapezoid shape)
let bellPath = CGMutablePath()
bellPath.move(to: CGPoint(x: bellX - bellWidth * 0.3, y: bellY - bellHeight))
bellPath.addLine(to: CGPoint(x: bellX + bellWidth * 0.3, y: bellY - bellHeight))
bellPath.addQuadCurve(
    to: CGPoint(x: bellX + bellWidth * 0.5, y: bellY),
    control: CGPoint(x: bellX + bellWidth * 0.5, y: bellY - bellHeight * 0.4)
)
bellPath.addLine(to: CGPoint(x: bellX - bellWidth * 0.5, y: bellY))
bellPath.addQuadCurve(
    to: CGPoint(x: bellX - bellWidth * 0.3, y: bellY - bellHeight),
    control: CGPoint(x: bellX - bellWidth * 0.5, y: bellY - bellHeight * 0.4)
)
bellPath.closeSubpath()
context.addPath(bellPath)
context.fillPath()

// Bell clapper (small circle at bottom)
context.addArc(
    center: CGPoint(x: bellX, y: bellY + bellHeight * 0.18),
    radius: bellWidth * 0.1,
    startAngle: 0,
    endAngle: .pi * 2,
    clockwise: false
)
context.fillPath()

// Bell handle (small arc on top)
context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.55))
context.setLineWidth(size * 0.012)
context.addArc(
    center: CGPoint(x: bellX, y: bellY - bellHeight - size * 0.008),
    radius: bellWidth * 0.12,
    startAngle: .pi,
    endAngle: 0,
    clockwise: true
)
context.strokePath()

// Save as PNG
guard let image = context.makeImage() else {
    print("Failed to create image")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("Failed to create image destination")
    exit(1)
}

CGImageDestinationAddImage(dest, image, nil)

if CGImageDestinationFinalize(dest) {
    print("Icon saved to \(outputPath)")
} else {
    print("Failed to save icon")
    exit(1)
}
