import AppKit
import ClipboardCore

@MainActor
enum DemoImage {
    static func make() -> ClipboardImage? {
        let sample = NSImage(size: NSSize(width: 960, height: 540), flipped: false) { rect in
            NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.30, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.49, green: 0.77, blue: 0.72, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 64, y: 310, width: 832, height: 156), xRadius: 24, yRadius: 24).fill()
            ("CopyShelf" as NSString).draw(at: NSPoint(x: 100, y: 356), withAttributes: [
                .font: NSFont.systemFont(ofSize: 54, weight: .bold), .foregroundColor: NSColor.black
            ])
            ("A screenshot worth keeping." as NSString).draw(at: NSPoint(x: 72, y: 216), withAttributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: NSColor.white
            ])
            ("Text and images, one clipboard history." as NSString).draw(at: NSPoint(x: 72, y: 150), withAttributes: [
                .font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.lightGray
            ])
            return true
        }
        guard let cgImage = sample.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return nil }
        return try? ClipboardImage(pngData: data)
    }
}
