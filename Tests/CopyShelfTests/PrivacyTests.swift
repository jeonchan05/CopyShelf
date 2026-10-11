import AppKit
import ClipboardCore
import Foundation
import Testing
@testable import CopyShelf

@MainActor
struct PrivacyTests {
    @Test func acknowledgingOwnWriteDoesNotSkipANewerExternalCopy() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false })
        var captured: [String] = []
        monitor.onText = { text, _ in captured.append(text) }
        let ownCount = board.clearContents()
        board.setString("synthetic own copy", forType: .string)
        #expect(board.changeCount == ownCount)
        board.clearContents()
        board.setString("synthetic newer copy", forType: .string)
        monitor.acknowledgeOwnWrite(changeCount: ownCount)
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured == ["synthetic newer copy"])
    }

    @Test func changingClipboardDuringReadDoesNotCaptureNewConcealedText() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false }, readText: { board in
            board.clearContents()
            board.setString("synthetic secret", forType: .string)
            board.setString("", forType: .init("org.nspasteboard.ConcealedType"))
            return "synthetic secret"
        })
        var captured: [String] = []
        monitor.onText = { text, _ in captured.append(text) }
        board.clearContents()
        board.setString("synthetic public text", forType: .string)
        monitor.poll()
        await monitor.finishCaptures()
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured.isEmpty)
    }

    @Test func secureInputStartingDuringReadPreventsCapture() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var secure = false
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { secure }, readText: { board in
            secure = true
            return board.string(forType: .string)
        })
        var captured: [String] = []
        monitor.onText = { text, _ in captured.append(text) }
        board.clearContents()
        board.setString("synthetic text", forType: .string)
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured.isEmpty)
    }

    @Test func markerAddedWithoutNewOwnershipAlsoPreventsCapture() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false }, readText: { board in
            board.setString("synthetic secret", forType: .string)
            board.setString("", forType: .init("org.nspasteboard.ConcealedType"))
            return "synthetic secret"
        })
        var captured: [String] = []
        monitor.onText = { text, _ in captured.append(text) }
        let count = board.clearContents()
        board.setString("synthetic public text", forType: .string)
        monitor.poll()
        await monitor.finishCaptures()
        #expect(board.changeCount == count)
        #expect(captured.isEmpty)
    }

    @Test func captureReadsStableTextOnceAndHonorsMarkersOnOtherItems() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false })
        var captured: [String] = []
        monitor.onText = { text, _ in captured.append(text) }
        board.clearContents()
        board.setString("synthetic public text", forType: .string)
        monitor.poll()
        await monitor.finishCaptures()
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured == ["synthetic public text"])
        let publicItem = NSPasteboardItem()
        publicItem.setString("another synthetic text", forType: .string)
        let concealedItem = NSPasteboardItem()
        concealedItem.setString("synthetic secret", forType: .string)
        concealedItem.setString("", forType: .init("org.nspasteboard.ConcealedType"))
        board.clearContents()
        board.writeObjects([publicItem, concealedItem])
        monitor.poll()
        await monitor.finishCaptures()
        #expect(captured == ["synthetic public text"])
    }

    @Test func clearingWaitsForQueuedWritesAndDoesNotRecreateTheArchive() throws {
        let root = Foundation.FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? Foundation.FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.json")
        let store = HistoryStore(demo: false, fileURL: url)
        for index in 0..<20 { store.record("synthetic item \(index)", source: "Test") }
        store.clear()
        #expect(store.history.clips.isEmpty)
        #expect(store.storageError == nil)
        #expect(!Foundation.FileManager.default.fileExists(atPath: url.path))
        store.finishWrites()
        #expect(!Foundation.FileManager.default.fileExists(atPath: url.path))
    }

    @Test func failedClearKeepsVisibleHistoryAndReportsFailure() throws {
        let root = Foundation.FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? Foundation.FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("private/history.json")
        let store = HistoryStore(demo: false, fileURL: url)
        store.record("synthetic text", source: "Test")
        store.finishWrites()
        let target = root.appendingPathComponent("outside.json")
        try Foundation.FileManager.default.moveItem(at: url, to: target)
        try Foundation.FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        store.clear()
        #expect(store.history.clips.map(\.text) == ["synthetic text"])
        #expect(store.storageError != nil)
        #expect(Foundation.FileManager.default.fileExists(atPath: target.path))
    }
}
