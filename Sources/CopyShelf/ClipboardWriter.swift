import AppKit
import ClipboardCore

struct ClipboardWriter {
    enum WriteError: Error { case unavailable, changed }

    @MainActor
    static func write(_ clip: Clip, to board: NSPasteboard = .general) throws -> Int {
        let previousCount = board.changeCount
        // Prepare compatibility data before replacing any existing clipboard content.
        let tiff = try clip.image?.tiffData()
        guard board.changeCount == previousCount else { throw WriteError.changed }
        let changeCount = board.clearContents()
        let success: Bool
        if let image = clip.image, let tiff {
            let item = NSPasteboardItem()
            guard item.setData(image.pngData, forType: .png), item.setData(tiff, forType: .tiff) else {
                throw WriteError.unavailable
            }
            success = board.writeObjects([item])
        } else { success = board.setString(clip.text, forType: .string) }
        guard success else { throw WriteError.unavailable }
        guard board.changeCount == changeCount else { throw WriteError.changed }
        return changeCount
    }
}
