import Foundation
import Testing
@testable import ClipboardCore

struct ClipboardCoreTests {
    @Test
    func testDuplicateMovesToFrontWithoutChangingItsIdentity() {
        var history = ClipboardHistory()
        history.record("first")
        let id = history.clips[0].id
        history.record("second")
        history.record("first", sourceName: "Editor")
        #expect(history.clips.map(\.text) == ["first", "second"])
        #expect(history.clips[0].id == id)
        #expect(history.clips[0].sourceName == "Editor")
        let repeated = history.record("first")
        #expect(!repeated)
    }

    @Test func testPreservesCodeWhitespaceAndBoundsHistory() {
        var history = ClipboardHistory(limit: 2)
        history.record("old")
        history.record("middle")
        let code = "  if ready {\n\tprint(\"안녕\")\n}\n"
        let recorded = history.record(code)
        #expect(recorded)
        #expect(history.clips.map(\.text) == [code, "middle"])
    }

    @Test func testRejectsBlankAndOversizedText() {
        var history = ClipboardHistory()
        let blank = history.record(" \n\t ")
        let oversized = history.record(String(repeating: "가", count: 30_000))
        #expect(!blank)
        #expect(!oversized)
        #expect(history.clips.isEmpty)
    }

    @Test func testSearchCombinesWordsAcrossTextAndSource() {
        var history = ClipboardHistory()
        history.record("배포 메모", sourceName: "Notes")
        history.record("Café release notes", sourceName: "Editor")
        #expect(history.search("CAFE editor").count == 1)
        #expect(history.search("배포 NOTES").count == 1)
        #expect(history.search("   ").count == 2)
        #expect(history.search("missing").isEmpty)
    }

    @Test func testSensitiveAndNonTextCapturePolicy() {
        #expect(!CapturePolicy.shouldCapture(types: ["org.nspasteboard.ConcealedType"], sourceBundleID: nil, secureInput: false))
        #expect(!CapturePolicy.shouldCapture(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.Passwords", secureInput: false))
        #expect(!CapturePolicy.shouldCapture(types: [], sourceBundleID: nil, secureInput: true))
        #expect(!CapturePolicy.shouldCapture(types: ["public.file-url"], sourceBundleID: nil, secureInput: false))
        #expect(CapturePolicy.shouldCapture(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.TextEdit", secureInput: false))
    }

    @Test func testSelectionClampsAtBothEndsAndHandlesEmptyResults() {
        #expect(Selection.moved(0, by: -1, count: 3) == 0)
        #expect(Selection.moved(2, by: 1, count: 3) == 2)
        #expect(Selection.moved(0, by: 1, count: 3) == 1)
        #expect(Selection.moved(0, by: 1, count: 0) == -1)
    }

    @Test func testPersistenceRoundTripReplacementAndClear() throws {
        let directory = Foundation.FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? Foundation.FileManager.default.removeItem(at: directory) }
        let file = HistoryFile(url: directory.appendingPathComponent("history.json"))
        #expect(try file.load() == [])
        let clips = [Clip(text: "exact\ntext", sourceName: "Test")]
        try file.save(clips)
        #expect(try file.load() == clips)
        let permissions = try Foundation.FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        try file.save([Clip(text: "replacement")])
        #expect(try file.load().first?.text == "replacement")
        try file.save([])
        #expect(!Foundation.FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func testMalformedArchiveReportsErrorInsteadOfSilentlyDiscardingIt() throws {
        let directory = Foundation.FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Foundation.FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? Foundation.FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        try Data("broken".utf8).write(to: url)
        #expect(throws: (any Error).self) { try HistoryFile(url: url).load() }
    }
}
