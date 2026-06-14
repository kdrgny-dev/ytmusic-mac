// Renders a 1024×1024 app icon PNG.
// Usage: swift scripts/make_icon.swift <output.png>

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

if let ctx = NSGraphicsContext.current?.cgContext {
    // Dark rounded-square background with subtle gradient
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset: CGFloat = 96 // macOS Big Sur+ icons leave a transparent margin
    let body = rect.insetBy(dx: inset, dy: inset)
    let corner: CGFloat = body.width * 0.225

    let bgPath = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
            CGColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: []
    )
    ctx.restoreGState()

    // Red play circle
    let circleDiameter = body.width * 0.55
    let circleRect = CGRect(
        x: body.midX - circleDiameter / 2,
        y: body.midY - circleDiameter / 2,
        width: circleDiameter,
        height: circleDiameter
    )
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: CGColor(red: 1, green: 0, blue: 0, alpha: 0.45))

    let redGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 1.00, green: 0.15, blue: 0.15, alpha: 1),
            CGColor(red: 0.78, green: 0.00, blue: 0.00, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.addEllipse(in: circleRect)
    ctx.clip()
    ctx.drawLinearGradient(
        redGradient,
        start: CGPoint(x: circleRect.minX, y: circleRect.maxY),
        end: CGPoint(x: circleRect.maxX, y: circleRect.minY),
        options: []
    )
    ctx.restoreGState()

    // White play triangle inside the circle
    let triSize = circleDiameter * 0.42
    let triCenter = CGPoint(x: circleRect.midX + triSize * 0.08, y: circleRect.midY)
    let triPath = CGMutablePath()
    triPath.move(to: CGPoint(x: triCenter.x - triSize / 2, y: triCenter.y + triSize / 1.7))
    triPath.addLine(to: CGPoint(x: triCenter.x - triSize / 2, y: triCenter.y - triSize / 1.7))
    triPath.addLine(to: CGPoint(x: triCenter.x + triSize / 1.4, y: triCenter.y))
    triPath.closeSubpath()
    ctx.addPath(triPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Failed to encode PNG\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outPath)
try! png.write(to: url)
print("Wrote \(outPath)")
