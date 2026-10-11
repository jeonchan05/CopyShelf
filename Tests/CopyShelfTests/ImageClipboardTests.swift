import AppKit
import ClipboardCore
import Foundation
import ImageIO
import Testing
@testable import CopyShelf

@MainActor
struct ImageClipboardTests {
    private func fixture() throws -> ClipboardImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<24 {
            for x in 0..<32 { bitmap.setColor(NSColor(calibratedRed: 0.3, green: 0.6, blue: 0.8, alpha: 1), atX: x, y: y) }
        }
        return try ClipboardImage(pngData: #require(bitmap.representation(using: .png, properties: [:])))
    }

    @Test func imageCopyProvidesPNGAndTIFFAndCanBeCapturedAgain() async throws {
        let image = try fixture()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false })
        var captured: [Clip] = []
        monitor.onClip = { captured.append($0) }
        let count = try ClipboardWriter.write(Clip(image: image), to: board)
        #expect(board.changeCount == count)
        #expect(board.data(forType: .png) == image.pngData)
        #expect(board.data(forType: .tiff) != nil)
        #expect(board.string(forType: .string) == nil)
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured.count == 1)
        #expect(captured.first?.image?.width == 32)
        #expect(captured.first?.image?.height == 24)
    }

    @Test func imageTakesPriorityOverACompanionURLString() async throws {
        let image = try fixture()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false })
        var captured: [Clip] = []
        monitor.onClip = { captured.append($0) }
        board.clearContents()
        board.setData(image.pngData, forType: .png)
        board.setString("https://example.com/synthetic-image", forType: .string)
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured.count == 1)
        #expect(captured.first?.isImage == true)
    }

    @Test func TIFFOnlyClipboardIsNormalisedToPNG() async throws {
        let image = try fixture()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false })
        var captured: [Clip] = []
        monitor.onClip = { captured.append($0) }
        board.clearContents()
        board.setData(try image.tiffData(), forType: .tiff)
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured.first?.image?.width == image.width)
        #expect(captured.first?.image?.height == image.height)
    }

    @Test func concealedImagesAndFileCopiesAreNotRead() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var reads = 0
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false }, readImage: { _, _ in reads += 1; return nil })
        for blocked in ["org.nspasteboard.ConcealedType", "public.file-url"] {
            board.clearContents()
            board.setData(Data([1]), forType: .png)
            board.setString("synthetic marker", forType: .init(blocked))
            monitor.poll()
        }
        await monitor.finishCaptures()
        #expect(reads == 0)
    }

    @Test func imageChangedOrMarkedDuringReadIsRejected() async throws {
        let image = try fixture()
        for newOwnership in [false, true] {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false }, readImage: { board, _ in
                if newOwnership { board.clearContents() }
                board.setData(image.pngData, forType: .png)
                board.setString("", forType: .init("org.nspasteboard.ConcealedType"))
                return image.pngData
            })
            var captured: [Clip] = []
            monitor.onClip = { captured.append($0) }
            board.clearContents()
            board.setData(image.pngData, forType: .png)
            monitor.poll()
            await monitor.finishCaptures()
            #expect(captured.isEmpty)
        }
    }

    @Test func pendingImageCannotReturnAfterPauseOrClear() async throws {
        let image = try fixture()
        for stopping in [false, true] {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false })
            var captured: [Clip] = []
            monitor.onClip = { captured.append($0) }
            board.clearContents()
            board.setData(image.pngData, forType: .png)
            monitor.poll()
            if stopping { monitor.stop() } else { monitor.invalidatePendingCaptures() }
            await monitor.finishCaptures()
            #expect(captured.isEmpty)
        }
    }

    @Test func slowImageAndLaterTextAreDeliveredInCopyOrder() async throws {
        let image = try fixture()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false })
        var captured: [Clip] = []
        monitor.onClip = { captured.append($0) }
        board.clearContents()
        board.setData(image.pngData, forType: .png)
        monitor.poll()
        board.clearContents()
        board.setString("newer synthetic text", forType: .string)
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured.count == 2)
        #expect(captured[0].isImage)
        #expect(captured[1].text == "newer synthetic text")
        #expect(captured[0].copiedAt <= captured[1].copiedAt)
    }

    @Test func invalidImageIsSkippedWithoutRecordingItsCompanionText() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false })
        var captured: [Clip] = []
        var skipped = 0
        monitor.onClip = { captured.append($0) }
        monitor.onSkippedImage = { skipped += 1 }
        board.clearContents()
        board.setData(Data("invalid image".utf8), forType: .png)
        board.setString("synthetic companion text", forType: .string)
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured.isEmpty)
        #expect(skipped == 1)
    }

    @Test func writerCoalescingStillPersistsTheLatestMixedHistory() throws {
        let root = Foundation.FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? Foundation.FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.json")
        let store = HistoryStore(demo: false, fileURL: url)
        store.record(Clip(image: try fixture(), sourceName: "Screenshot"))
        for index in 0..<30 { store.record("synthetic \(index)", source: "Test") }
        store.finishWrites()
        #expect(try HistoryFile(url: url).load() == store.history.clips)
        store.clear()
        #expect(store.history.clips.isEmpty)
        #expect(!Foundation.FileManager.default.fileExists(atPath: url.path))
    }
}
