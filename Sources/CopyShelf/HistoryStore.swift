import AppKit
import ClipboardCore
import Foundation

@MainActor
final class HistoryStore {
    private(set) var history = ClipboardHistory()
    private let file: HistoryFile
    private let writer: HistoryWriter
    private let demo: Bool
    private var canSave = true
    private var writeGeneration = 0
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    private(set) var storageError: String?

    init(demo: Bool, fileURL: URL? = nil) {
        self.demo = demo
        let directory = Foundation.FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopyShelf", isDirectory: true)
        file = HistoryFile(url: fileURL ?? directory.appendingPathComponent("history.json"))
        writer = HistoryWriter(file: file)
        if demo {
            history.record("회의 메모\n금요일까지 첫 버전 테스트\n단축키 · 검색 · 붙여넣기", sourceName: "Notes")
            history.record("https://developer.apple.com/documentation/appkit", sourceName: "Safari")
            history.record("git switch -c feature/clipboard-search", sourceName: "Terminal")
            history.record("텍스트 기록과 검색부터 작게 시작합니다.", sourceName: "TextEdit")
            if let image = DemoImage.make() { history.record(image, sourceName: "Screenshot") }
        } else {
            do { history = ClipboardHistory(clips: try file.load()) }
            catch {
                canSave = false
                storageError = L("Saved history could not be read. It has been kept on disk. Clear history to start fresh.",
                                 "저장한 기록을 읽지 못했습니다. 파일은 유지됩니다. 기록을 지우면 새로 시작할 수 있습니다.")
            }
        }
    }

    func record(_ text: String, source: String) {
        record(Clip(text: text, sourceName: source))
    }

    func record(_ clip: Clip) {
        let changed: Bool
        if let image = clip.image { changed = history.record(image, sourceName: clip.sourceName, at: clip.copiedAt) }
        else { changed = history.record(clip.text, sourceName: clip.sourceName, at: clip.copiedAt) }
        guard changed else { return }
        save()
        onChange?()
    }

    func remove(id: UUID) {
        history.remove(id: id)
        save()
        onChange?()
    }

    func clear() {
        writeGeneration += 1
        // Complete older writes and remove the file before reporting that clearing succeeded.
        // A failed deletion must not hide the remaining history from the user.
        if !demo {
            do { try writer.clear() }
            catch {
                storageError = L("History could not be cleared. The saved file has been kept. Check its path and permissions.",
                                 "기록을 지우지 못했습니다. 저장 파일은 유지됩니다. 경로와 접근 권한을 확인해 주세요.")
                onError?(storageError!)
                return
            }
        }
        history.clear()
        canSave = true
        storageError = nil
        onChange?()
    }

    private func save() {
        guard !demo, canSave else { return }
        let clips = history.clips
        writeGeneration += 1
        let generation = writeGeneration
        writer.submit(clips, generation: generation) { [weak self] completedGeneration, success in
            DispatchQueue.main.async {
                guard let self, self.writeGeneration == completedGeneration else { return }
                if success {
                    if self.storageError != nil { self.storageError = nil; self.onChange?() }
                } else {
                    self.storageError = L("History could not be saved. Check the permissions or free space in Application Support.",
                                          "기록을 저장하지 못했습니다. Application Support의 접근 권한과 남은 공간을 확인해 주세요.")
                    self.onError?(self.storageError!)
                }
            }
        }
    }

    func finishWrites() { writer.finish() }
}
