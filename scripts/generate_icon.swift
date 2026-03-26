#!/usr/bin/env swift
// VoiceFlow 图标生成器 — 用 AppKit 原生绘制，导出标准 iconset

import AppKit
import Foundation

let size: CGFloat = 1024
let margin: CGFloat = 100
let iconSize = size - margin * 2
let corner: CGFloat = iconSize * 0.22  // Apple 圆角比例

func drawIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fatalError("No graphics context")
    }

    let iconRect = NSRect(x: margin, y: margin, width: iconSize, height: iconSize)
    let path = NSBezierPath(roundedRect: iconRect, xRadius: corner, yRadius: corner)

    // 背景渐变：春绿 → 天青蓝（对角线）
    ctx.saveGState()
    path.addClip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.30, green: 0.80, blue: 0.58, alpha: 1.0),  // 春绿（左上）
        CGColor(red: 0.22, green: 0.62, blue: 0.82, alpha: 1.0),  // 天青蓝（右下）
    ]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: margin, y: size - margin),        // 左上（CoreGraphics Y 轴翻转）
            end: CGPoint(x: size - margin, y: margin),           // 右下
            options: []
        )
    }

    // 顶部高光（白色半透明渐变）
    for i in 0..<200 {
        let y = size - margin - CGFloat(i)  // 从顶部往下
        let t = CGFloat(i) / 200.0
        let alpha = 0.15 * pow(1.0 - t, 2.5)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: size - margin, y: y))
        ctx.strokePath()
    }

    ctx.restoreGState()

    // 声波条
    let barHeights: [CGFloat] = [0.26, 0.50, 0.88, 0.50, 0.26]
    let barWidth: CGFloat = 50
    let barGap: CGFloat = 34
    let totalWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * barGap
    let startX = (size - totalWidth) / 2
    let maxH = iconSize * 0.46
    let cy = size / 2

    for (i, hr) in barHeights.enumerated() {
        let x = startX + CGFloat(i) * (barWidth + barGap)
        let h = maxH * hr
        let barRect = NSRect(x: x, y: cy - h / 2, width: barWidth, height: h)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)

        // 白色微透明
        NSColor(white: 1.0, alpha: 0.92).setFill()
        barPath.fill()
    }

    image.unlockFocus()
    return image
}

func saveAsPNG(_ image: NSImage, to path: String, pixelSize: Int) {
    let targetSize = NSSize(width: pixelSize, height: pixelSize)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = targetSize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: targetSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

// main
let basePath = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("assets")

try! FileManager.default.createDirectory(at: basePath, withIntermediateDirectories: true)

print("Generating VoiceFlow icon...")
let icon = drawIcon()

// 保存 1024x1024
let iconPath = basePath.appendingPathComponent("icon.png").path
saveAsPNG(icon, to: iconPath, pixelSize: 1024)
print("Saved: assets/icon.png")

// 生成 iconset
let iconsetPath = basePath.appendingPathComponent("VoiceFlow.iconset")
try? FileManager.default.createDirectory(at: iconsetPath, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (sz, name) in sizes {
    saveAsPNG(icon, to: iconsetPath.appendingPathComponent(name).path, pixelSize: sz)
}
print("Generated iconset")

// iconutil 转 .icns
let icnsPath = basePath.appendingPathComponent("VoiceFlow.icns").path
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetPath.path, "-o", icnsPath]
try! proc.run()
proc.waitUntilExit()
print("Created: assets/VoiceFlow.icns")
