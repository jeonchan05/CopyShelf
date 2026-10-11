import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()

        let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 196, yRadius: 196)
        NSGraphicsContext.saveGraphicsState()
        let tileShadow = NSShadow()
        tileShadow.shadowColor = color(0.03, 0.08, 0.12, 0.24)
        tileShadow.shadowBlurRadius = 26
        tileShadow.shadowOffset = NSSize(width: 0, height: -10)
        tileShadow.set()
        color(0.08, 0.15, 0.22).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: color(0.07, 0.14, 0.21), ending: color(0.15, 0.29, 0.37))!.draw(in: tile, angle: 80)
        color(1, 1, 1, 0.16).setStroke()
        tile.lineWidth = 3
        tile.stroke()

        func drawSheet(rect: NSRect, rotation: CGFloat, top: NSColor, bottom: NSColor, content: () -> Void = {}) {
            NSGraphicsContext.saveGraphicsState()
            let rotationTransform = NSAffineTransform()
            rotationTransform.translateX(by: rect.midX, yBy: rect.midY)
            rotationTransform.rotate(byDegrees: rotation)
            rotationTransform.translateX(by: -rect.midX, yBy: -rect.midY)
            rotationTransform.concat()
            let paper = NSBezierPath(roundedRect: rect, xRadius: 52, yRadius: 52)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = color(0.01, 0.05, 0.09, 0.28)
            shadow.shadowBlurRadius = 35
            shadow.shadowOffset = NSSize(width: 0, height: -18)
            shadow.set()
            bottom.setFill()
            paper.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(starting: bottom, ending: top)!.draw(in: paper, angle: 90)
            color(1, 1, 1, 0.35).setStroke()
            paper.lineWidth = 3
            paper.stroke()
            content()
            NSGraphicsContext.restoreGraphicsState()
        }
        drawSheet(rect: NSRect(x: 252, y: 222, width: 424, height: 542), rotation: -10,
                  top: color(0.50, 0.86, 0.77), bottom: color(0.28, 0.66, 0.61))
        drawSheet(rect: NSRect(x: 338, y: 282, width: 424, height: 542), rotation: 6,
                  top: color(1, 1, 0.98), bottom: color(0.89, 0.94, 0.93)) {
            let tag = NSBezierPath(roundedRect: NSRect(x: 395, y: 708, width: 102, height: 34), xRadius: 17, yRadius: 17)
            color(0.21, 0.62, 0.54).setFill()
            tag.fill()
            for (index, width) in [286, 286, 184].enumerated() {
                let line = NSBezierPath(roundedRect: NSRect(x: 395, y: 603 - index * 90, width: width, height: 27), xRadius: 13.5, yRadius: 13.5)
                color(0.16, 0.30, 0.35, index == 2 ? 0.64 : 0.84).setFill()
                line.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
