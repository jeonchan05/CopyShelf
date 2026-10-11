import Darwin
import Foundation
import Testing
@testable import ClipboardCore

struct SecurityTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = Foundation.FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Foundation.FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? Foundation.FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test func fileSymlinkCannotReadReplaceOrDeleteItsTarget() throws {
        try withDirectory { root in
            let target = root.appendingPathComponent("outside.json")
            let file = HistoryFile(url: root.appendingPathComponent("private/history.json"))
            try file.save([Clip(text: "synthetic outside text")])
            try Foundation.FileManager.default.moveItem(at: file.url, to: target)
            try Foundation.FileManager.default.createSymbolicLink(at: file.url, withDestinationURL: target)
            let original = try Data(contentsOf: target)
            #expect(throws: (any Error).self) { try file.load() }
            #expect(throws: (any Error).self) { try file.save([Clip(text: "replacement")]) }
            #expect(throws: (any Error).self) { try file.save([]) }
            #expect(try Data(contentsOf: target) == original)
        }
    }

    @Test func directorySymlinkCannotChangeTargetPermissionsOrContents() throws {
        try withDirectory { root in
            let outside = root.appendingPathComponent("outside")
            let outsideFile = HistoryFile(url: outside.appendingPathComponent("history.json"))
            try outsideFile.save([Clip(text: "synthetic private text")])
            try Foundation.FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outside.path)
            let link = root.appendingPathComponent("linked")
            try Foundation.FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            let file = HistoryFile(url: link.appendingPathComponent("history.json"))
            #expect(throws: (any Error).self) { try file.load() }
            #expect(throws: (any Error).self) { try file.save([Clip(text: "replacement")]) }
            #expect(throws: (any Error).self) { try file.save([]) }
            let permissions = try Foundation.FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? Int
            #expect(permissions == 0o755)
            #expect(try outsideFile.load().first?.text == "synthetic private text")
        }
    }

    @Test func hardLinksAndFIFOsAreRejectedWithoutBlocking() throws {
        try withDirectory { root in
            let file = HistoryFile(url: root.appendingPathComponent("private/history.json"))
            try file.save([Clip(text: "synthetic")])
            let link = root.appendingPathComponent("hardlink")
            try Foundation.FileManager.default.linkItem(at: file.url, to: link)
            #expect(throws: (any Error).self) { try file.load() }
            #expect(throws: (any Error).self) { try file.save([]) }
            try Foundation.FileManager.default.removeItem(at: link)
            try file.save([])
            #expect(mkfifo(file.url.path, 0o600) == 0)
            #expect(throws: (any Error).self) { try file.load() }
            #expect(throws: (any Error).self) { try file.save([]) }
        }
    }

    @Test func oversizedSparseFileIsRejectedBeforeReadingItsContents() throws {
        try withDirectory { root in
            let file = HistoryFile(url: root.appendingPathComponent("private/history.json"))
            try file.save([Clip(text: "synthetic")])
            let descriptor = open(file.url.path, O_WRONLY)
            #expect(descriptor >= 0)
            guard descriptor >= 0 else { return }
            defer { close(descriptor) }
            #expect(ftruncate(descriptor, off_t(HistoryFile.maximumArchiveBytes + 1)) == 0)
            #expect(throws: HistoryFile.ArchiveError.oversizedArchive) { try file.load() }
        }
    }

    @Test func archiveRejectsTooManyItemsOversizedTextAndDuplicateIDs() throws {
        struct Archive: Encodable { let version = 1; let clips: [Clip] }
        try withDirectory { root in
            let file = HistoryFile(url: root.appendingPathComponent("private/history.json"))
            try file.save([Clip(text: "synthetic")])
            let duplicate = Clip(text: "synthetic duplicate")
            let invalid: [[Clip]] = [
                (0...200).map { Clip(text: "item \($0)") },
                [Clip(text: String(repeating: "x", count: 65_537))],
                [duplicate, duplicate],
                [Clip(text: "valid text", sourceName: String(repeating: "x", count: 1025))]
            ]
            for clips in invalid {
                try JSONEncoder().encode(Archive(clips: clips)).write(to: file.url)
                #expect(throws: HistoryFile.ArchiveError.invalidContents) { try file.load() }
                #expect(throws: HistoryFile.ArchiveError.invalidContents) { try file.save(clips) }
            }
        }
    }

    @Test func validControlTextAndMaximumHistoryRoundTrip() throws {
        try withDirectory { root in
            let file = HistoryFile(url: root.appendingPathComponent("private/history.json"))
            let clips = (0..<200).map { Clip(text: "item \($0)\n" + String(repeating: "\u{0001}", count: 1024)) }
            try file.save(clips)
            #expect(try file.load() == clips)
            let permissions = try Foundation.FileManager.default.attributesOfItem(atPath: file.url.deletingLastPathComponent().path)[.posixPermissions] as? Int
            #expect(permissions == 0o700)
            #expect(try Foundation.FileManager.default.contentsOfDirectory(atPath: file.url.deletingLastPathComponent().path) == ["history.json"])
        }
    }

    @Test func olderBroadPermissionsAreRestrictedOnLoad() throws {
        try withDirectory { root in
            let file = HistoryFile(url: root.appendingPathComponent("private/history.json"))
            try file.save([Clip(text: "synthetic")])
            try Foundation.FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.url.path)
            try Foundation.FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.url.deletingLastPathComponent().path)
            _ = try file.load()
            #expect(try Foundation.FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int == 0o600)
            #expect(try Foundation.FileManager.default.attributesOfItem(atPath: file.url.deletingLastPathComponent().path)[.posixPermissions] as? Int == 0o700)
        }
    }

    @Test func pendingPasteRejectsChangedClipboardAndSupersededRequests() {
        let first = PasteAttempt(clipboardChangeCount: 12)
        let second = PasteAttempt(clipboardChangeCount: 13)
        #expect(first.isCurrent(first.id))
        #expect(first.clipboardIsUnchanged(12))
        #expect(!first.clipboardIsUnchanged(13))
        #expect(!first.isCurrent(second.id))
        #expect(!second.isCurrent(nil))
    }

    @Test func declaredPasswordManagerIsExcludedEvenAfterForegroundAppChanges() {
        #expect(!CapturePolicy.shouldCapture(types: ["public.utf8-plain-text"],
                    sourceBundleID: "com.apple.TextEdit", secureInput: false,
                    additionalSourceBundleIDs: ["com.1password.1password"]))
        #expect(!CapturePolicy.shouldCapture(types: ["public.utf8-plain-text"],
                    sourceBundleID: "com.apple.Passwords", secureInput: false,
                    additionalSourceBundleIDs: ["com.apple.TextEdit"]))
    }
}
