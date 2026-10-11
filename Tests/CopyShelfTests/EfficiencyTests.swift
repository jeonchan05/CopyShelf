import AppKit
import ClipboardCore
import Foundation
import Testing
@testable import CopyShelf

private final class WriteCompletions: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    func append(_ value: Int) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var generations: [Int] { lock.lock(); defer { lock.unlock() }; return values }
}

@MainActor
struct EfficiencyTests {
    @Test func burstWritesSaveTheLatestSnapshotAndQuitFlushesWithoutWaiting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = HistoryFile(url: root.appendingPathComponent("history.json"))
        let writer = HistoryWriter(file: file, coalescingInterval: 60)
        let completed = WriteCompletions()
        for generation in 1...20 {
            writer.submit([Clip(text: "sample \(generation)")], generation: generation) { value, ok in
                if ok { completed.append(value) }
            }
        }
        #expect(try file.load().isEmpty)
        writer.finish()
        #expect(completed.generations == [20])
        #expect(try file.load().map(\.text) == ["sample 20"])
    }

    @Test func clearCancelsDelayedWritesAndCannotRecreateHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = HistoryFile(url: root.appendingPathComponent("history.json"))
        let writer = HistoryWriter(file: file, coalescingInterval: 60)
        writer.submit([Clip(text: "saved sample")], generation: 1) { _, _ in }
        writer.finish()
        writer.submit([Clip(text: "pending sample")], generation: 2) { _, _ in }
        try writer.clear()
        writer.finish()
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func idleChecksAreThrottledButEveryNewCopyChecksAccess() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var now = 0.0
        var reads = 0
        var statuses: [Bool] = []
        var blocked = false
        var captured: [String] = []
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false },
            readAccessBlocked: { _ in reads += 1; return blocked }, uptime: { now })
        monitor.onAccessIssue = { statuses.append($0) }
        monitor.onText = { text, _ in captured.append(text) }
        for _ in 0..<100 { monitor.poll() }
        #expect(reads == 1)
        #expect(statuses == [false])
        board.clearContents(); board.setString("allowed sample", forType: .string)
        monitor.poll(); await monitor.finishCaptures()
        #expect(reads == 2)
        blocked = true
        board.clearContents(); board.setString("blocked sample", forType: .string)
        monitor.poll(); await monitor.finishCaptures()
        #expect(reads == 3)
        #expect(captured == ["allowed sample"])
        #expect(statuses == [false, true])
        now = 2.1; blocked = false
        monitor.poll()
        #expect(reads == 4)
        #expect(statuses == [false, true, false])
        await monitor.finishCaptures()
        #expect(captured == ["allowed sample"])
    }

    @Test func suspendedCaptureSkipsSessionCopiesAndResumesOnlyNewCopies() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var reads = 0
        var captured: [String] = []
        let monitor = ClipboardMonitor(pasteboard: board, secureInput: { false }, readText: {
            reads += 1; return $0.string(forType: .string)
        })
        monitor.onText = { text, _ in captured.append(text) }
        monitor.setSuspended(true)
        board.clearContents(); board.setString("inactive session sample", forType: .string)
        monitor.poll(); await monitor.finishCaptures()
        #expect(reads == 0)
        monitor.setSuspended(false)
        monitor.poll(); await monitor.finishCaptures()
        #expect(reads == 0)
        board.clearContents(); board.setString("new active sample", forType: .string)
        monitor.poll(); await monitor.finishCaptures()
        #expect(captured == ["new active sample"])
    }

    @Test func hiddenHistoryDoesNotBuildRowsAndHidingReleasesResults() {
        let store = HistoryStore(demo: true)
        let panel = HistoryPanel(store: store)
        let table = NSTableView()
        store.onChange = { panel.refresh() }
        store.record("new demo sample", source: "Test")
        #expect(panel.numberOfRows(in: table) == 0)
        panel.refresh(force: true)
        #expect(panel.numberOfRows(in: table) == store.history.clips.count)
        panel.hide()
        #expect(panel.numberOfRows(in: table) == 0)
    }

    @Test func reusingAnImageRowForTextRemovesTheOldImage() throws {
        let image = try #require(DemoImage.make())
        let row = HistoryRowView(frame: .zero)
        row.configure(Clip(image: image), thumbnail: NSImage(size: NSSize(width: 20, height: 20)))
        #expect(row.imageView?.image != nil)
        row.configure(Clip(text: "new text"), thumbnail: nil)
        #expect(row.imageView?.image == nil)
        #expect(row.imageView?.isHidden == true)
        #expect(row.textField?.stringValue == "new text")
        row.releaseContent()
        #expect(row.textField?.stringValue.isEmpty == true)
    }

    @Test func boundedPreviewPreservesUnicodeAndOriginalText() {
        let text = "  가\t👨‍👩‍👧‍👦\n나  " + String(repeating: "긴 문장 ", count: 4000)
        let clip = Clip(text: text)
        #expect(clip.preview(maximumCharacters: 5) == "가 👨‍👩‍👧‍👦 나")
        #expect(clip.preview(maximumCharacters: 350).count == 350)
        #expect(clip.preview(maximumCharacters: 0).isEmpty)
        #expect(clip.text == text)
    }
}
