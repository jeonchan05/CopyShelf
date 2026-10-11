import AppKit
import ClipboardCore
import Foundation

func L(_ english: String, _ korean: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("ko") == true ? korean : english
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class HistoryRowView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("history-row")
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let thumbnailView = NSImageView()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.timeStyle = .short
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        textField = previewLabel
        imageView = thumbnailView
        previewLabel.font = .systemFont(ofSize: 14, weight: .medium)
        previewLabel.maximumNumberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [previewLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 5
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let content = NSStackView(views: [thumbnailView, labels])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            thumbnailView.widthAnchor.constraint(equalToConstant: 72),
            thumbnailView.heightAnchor.constraint(equalToConstant: 48),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            previewLabel.widthAnchor.constraint(equalTo: labels.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ clip: Clip, thumbnail: NSImage?) {
        let title = clip.image.map { L("Image", "이미지") + " · \($0.width) × \($0.height)" }
            ?? clip.preview(maximumCharacters: 350)
        previewLabel.stringValue = title
        let source = clip.sourceName.isEmpty ? L("Copied item", "복사한 항목") : clip.sourceName
        detailLabel.stringValue = "\(source)  ·  \(Self.timeFormatter.string(from: clip.copiedAt))"
        thumbnailView.image = clip.isImage ? thumbnail : nil
        thumbnailView.isHidden = !clip.isImage
        thumbnailView.setAccessibilityLabel(clip.isImage ? title : "")
        toolTip = clip.isImage ? title : String(clip.text.prefix(1000))
    }

    func releaseContent() {
        thumbnailView.image = nil
        previewLabel.stringValue = ""
        detailLabel.stringValue = ""
        toolTip = nil
    }
}

@MainActor
final class HistoryPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    let panel: NSPanel
    private let store: HistoryStore
    private let search = NSSearchField()
    private let table = NSTableView()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var captureState = ""
    private var results: [Clip] = []
    private var keyboardMonitor: Any?
    private let thumbnails = NSCache<NSString, NSImage>()
    var onPaste: ((Clip) -> Void)?
    var onCopy: ((Clip) -> Void)?
    var onSettings: (() -> Void)?
    var onDismiss: (() -> Void)?

    init(store: HistoryStore) {
        self.store = store
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
                         styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        thumbnails.countLimit = 32
        thumbnails.totalCostLimit = 4 * 1024 * 1024
        panel.title = "CopyShelf"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        buildContent()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == [.command], event.keyCode == 8 { self.copySelected(); return nil }
            guard modifiers.isEmpty else { return event }
            switch event.keyCode {
            case 125: self.moveSelection(by: 1); return nil
            case 126: self.moveSelection(by: -1); return nil
            case 36, 76: self.pasteSelected(); return nil
            case 53: self.dismiss(); return nil
            default: return event
            }
        }
        refresh(resetSelection: true)
    }

    private func buildContent() {
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        panel.contentView = root

        search.placeholderString = L("Search text, images or app name", "텍스트·이미지·앱 이름 검색")
        search.font = .systemFont(ofSize: 15)
        search.controlSize = .large
        search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = false
        search.delegate = self
        search.setAccessibilityLabel(L("Search clipboard history", "클립보드 기록 검색"))

        table.headerView = nil
        table.rowHeight = 68
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.style = .fullWidth
        table.focusRingType = .none
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClick)
        table.setAccessibilityLabel(L("Clipboard history", "클립보드 기록"))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        empty.alignment = .center
        empty.font = .systemFont(ofSize: 14)
        empty.textColor = .secondaryLabelColor
        let listContainer = NSView()
        listContainer.addSubview(scroll)
        listContainer.addSubview(empty)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        empty.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            empty.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor),
            empty.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: 28),
            empty.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: -28)
        ])

        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        status.isHidden = true
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let settings = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: L("Settings", "설정")) ?? NSImage(),
                                target: self, action: #selector(openSettings))
        settings.bezelStyle = .regularSquare
        settings.isBordered = false
        settings.toolTip = L("Settings · Command-Comma", "설정 · ⌘,")
        settings.setAccessibilityLabel(L("Settings", "설정"))
        let header = NSStackView(views: [search, settings])
        header.orientation = .horizontal
        header.spacing = 10
        let keys = NSTextField(labelWithString: L("↑ ↓ Select   ↩ Paste   Esc Close", "↑ ↓ 선택   ↩ 붙여넣기   Esc 닫기"))
        keys.font = .systemFont(ofSize: 11)
        keys.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [countLabel, NSView(), keys])
        footer.orientation = .horizontal
        footer.spacing = 8
        let stack = NSStackView(views: [header, listContainer, status, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            search.heightAnchor.constraint(equalToConstant: 32),
            settings.widthAnchor.constraint(equalToConstant: 28),
            settings.heightAnchor.constraint(equalToConstant: 28),
            listContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            listContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        listContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    func show() {
        search.stringValue = ""
        refresh(resetSelection: true, force: true)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2 + 65))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }

    func hide() { panel.orderOut(nil); releaseDisplay() }
    func dismiss() { hide(); onDismiss?() }
    func windowDidResignKey(_ notification: Notification) {
        if panel.attachedSheet == nil { hide() }
    }

    private func releaseDisplay() {
        for row in 0..<table.numberOfRows {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HistoryRowView)?.releaseContent()
        }
        results.removeAll()
        thumbnails.removeAllObjects()
        table.reloadData()
    }

    func updateStatus(recording: Bool, accessBlocked: Bool, demo: Bool) {
        captureState = demo ? L("Preview", "미리보기")
            : (accessBlocked ? L("Access needed", "접근 필요")
                : (recording ? L("Recording", "기록 중") : L("Paused", "일시 정지")))
        countLabel.toolTip = demo ? L("Sample history. Your clipboard is not read or saved.", "예시 기록입니다. 클립보드를 읽거나 저장하지 않습니다.") : nil
        if let error = store.storageError { status.stringValue = error }
        else if accessBlocked && !demo {
            status.stringValue = L("Allow clipboard access in System Settings to record new copies.", "새 복사를 기록하려면 시스템 설정에서 클립보드 접근을 허용해 주세요.")
        } else { status.stringValue = "" }
        status.isHidden = status.stringValue.isEmpty
        updateCount()
    }

    private func updateCount() {
        let total = store.history.clips.count
        let count = search.stringValue.isEmpty ? "\(total)" : "\(results.count) / \(total)"
        countLabel.stringValue = (captureState.isEmpty ? "" : captureState + " · ") + count + L(" items", "개")
    }

    func showError(_ message: String) { status.stringValue = message; status.isHidden = false }

    func refresh(resetSelection: Bool = false, force: Bool = false) {
        guard force || panel.isVisible else { return }
        if store.history.clips.isEmpty { thumbnails.removeAllObjects() }
        let selectedID = selectedClip?.id
        results = store.history.search(search.stringValue)
        table.reloadData()
        let index = resetSelection ? 0 : (results.firstIndex(where: { $0.id == selectedID }) ?? 0)
        if !results.isEmpty {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        }
        empty.isHidden = !results.isEmpty
        empty.stringValue = search.stringValue.isEmpty
            ? L("Your next copy goes here.\nCopy text or use Control-Shift-Command-4 for a screenshot.", "다음 복사 내용이 여기에 표시됩니다.\n텍스트를 복사하거나 ⌃⇧⌘4로 화면을 캡처해 보세요.")
            : L("No matching items.\nTry another word, 'image', or an app name.", "일치하는 기록이 없습니다.\n다른 단어, ‘이미지’, 앱 이름으로 검색해 보세요.")
        updateCount()
    }

    private var selectedClip: Clip? {
        let row = table.selectedRow
        return results.indices.contains(row) ? results[row] : nil
    }

    private func moveSelection(by delta: Int) {
        let row = Selection.moved(table.selectedRow, by: delta, count: results.count)
        guard row >= 0 else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func pasteSelected() {
        guard let clip = selectedClip else { NSSound.beep(); return }
        onPaste?(clip)
    }

    private func copySelected() {
        // Let Command-C copy highlighted search text before treating it as a history action.
        if let editor = panel.firstResponder as? NSTextView, editor.selectedRange().length > 0 {
            editor.copy(nil)
            return
        }
        guard let clip = selectedClip else { return }
        onCopy?(clip)
        dismiss()
    }

    func controlTextDidChange(_ notification: Notification) { refresh(resetSelection: true) }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let clip = results[row]
        let cell = (tableView.makeView(withIdentifier: HistoryRowView.reuseID, owner: self) as? HistoryRowView)
            ?? HistoryRowView(frame: .zero)
        cell.configure(clip, thumbnail: clip.image.flatMap { thumbnailImage($0) })
        return cell
    }

    private func thumbnailImage(_ image: ClipboardImage) -> NSImage? {
        let key = image.fingerprint as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let decoded = image.thumbnail() else { return nil }
        let thumbnail = NSImage(cgImage: decoded, size: .zero)
        thumbnails.setObject(thumbnail, forKey: key, cost: decoded.width * decoded.height * 4)
        return thumbnail
    }

    @objc private func doubleClick() { pasteSelected() }
    @objc private func openSettings() { onSettings?() }
}
