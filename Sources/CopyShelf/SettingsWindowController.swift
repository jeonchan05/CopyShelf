import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let loginItem: LoginItemController
    private let recording: () -> Bool
    private let setRecording: (Bool) -> Void
    private let recordingButton = NSButton(checkboxWithTitle: L("Record in the background", "백그라운드에서 기록"), target: nil, action: nil)
    private let loginButton = NSButton(checkboxWithTitle: L("Launch at login", "로그인 시 자동 실행"), target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let onClear: () -> Void
    private let shortcut: () -> KeyboardShortcut
    private let setShortcut: (KeyboardShortcut) throws -> Void
    private let shortcutButton = NSButton(title: "", target: nil, action: nil)
    private let shortcutStatus = NSTextField(wrappingLabelWithString: "")
    private var shortcutMonitor: Any?
    private var lastError: String?

    init(loginItem: LoginItemController, recording: @escaping () -> Bool, setRecording: @escaping (Bool) -> Void, onClear: @escaping () -> Void = {}, shortcut: @escaping () -> KeyboardShortcut, setShortcut: @escaping (KeyboardShortcut) throws -> Void) {
        self.loginItem = loginItem
        self.recording = recording
        self.setRecording = setRecording
        self.onClear = onClear
        self.shortcut = shortcut
        self.setShortcut = setShortcut
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = L("CopyShelf Settings", "CopyShelf 설정")
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildContent()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildContent() {
        guard let window else { return }
        let root = NSVisualEffectView()
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        window.contentView = root

        let shortcutLabel = NSTextField(labelWithString: L("Open history", "기록 열기"))
        shortcutLabel.font = .systemFont(ofSize: 13, weight: .medium)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.target = self
        shortcutButton.action = #selector(recordShortcut)
        shortcutButton.isEnabled = !loginItem.demo
        shortcutButton.setAccessibilityLabel(L("Change history shortcut", "기록 단축키 변경"))
        shortcutButton.toolTip = L("Click, then press your shortcut. Escape cancels.", "클릭하고 원하는 단축키를 누르세요. Esc로 취소합니다.")
        let shortcutRow = NSStackView(views: [shortcutLabel, NSView(), shortcutButton])
        shortcutRow.orientation = .horizontal
        shortcutStatus.font = .systemFont(ofSize: 12)
        shortcutStatus.textColor = .secondaryLabelColor
        shortcutStatus.stringValue = L("Click the shortcut to change it. Include Command or Control.", "단축키를 클릭해 변경합니다. ⌘ 또는 ⌃를 포함해 주세요.")
        recordingButton.target = self
        recordingButton.action = #selector(changeRecording)
        recordingButton.isEnabled = !loginItem.demo
        let recordingHelp = NSTextField(wrappingLabelWithString: L(
            "Keep recording when history is closed. Pause is remembered after restarting.",
            "기록 창을 닫아도 계속 기록합니다. 일시 정지는 다음 실행에도 유지됩니다."))
        loginButton.target = self
        loginButton.action = #selector(changeLoginItem)
        loginButton.allowsMixedState = true
        loginButton.isEnabled = !loginItem.demo
        let loginHelp = NSTextField(wrappingLabelWithString: L(
            "Start in the menu bar when you log in to your Mac.",
            "Mac에 로그인하면 메뉴 막대에서 실행합니다."))
        for label in [recordingHelp, loginHelp, loginStatus] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
        }
        let systemSettings = NSButton(title: L("Open Login Items Settings…", "로그인 항목 설정 열기…"), target: self, action: #selector(openSystemSettings))
        systemSettings.bezelStyle = .rounded
        systemSettings.isEnabled = !loginItem.demo
        let access = NSButton(title: L("Allow automatic paste…", "자동 붙여넣기 허용…"), target: self, action: #selector(openPasteSettings))
        access.bezelStyle = .rounded
        access.isEnabled = !loginItem.demo
        let clear = NSButton(title: L("Clear history…", "기록 지우기…"), target: self, action: #selector(clearHistory))
        clear.bezelStyle = .rounded
        clear.isEnabled = !loginItem.demo
        let actions = NSStackView(views: [access, NSView(), clear])
        actions.orientation = .horizontal
        actions.spacing = 8
        let stack = NSStackView(views: [shortcutRow, shortcutStatus, recordingButton, recordingHelp, loginButton, loginHelp, loginStatus, systemSettings, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(6, after: recordingButton)
        stack.setCustomSpacing(18, after: recordingHelp)
        stack.setCustomSpacing(6, after: loginButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
            shortcutRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shortcutStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recordingHelp.widthAnchor.constraint(equalTo: stack.widthAnchor),
            loginHelp.widthAnchor.constraint(equalTo: stack.widthAnchor),
            loginStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func show() {
        refresh(clearError: true)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func refresh(clearError: Bool = false) {
        if clearError { lastError = nil }
        if shortcutMonitor == nil { shortcutButton.title = shortcut().display }
        recordingButton.state = recording() ? .on : .off
        switch loginItem.state {
        case .enabled:
            loginButton.state = .on
            loginStatus.stringValue = L("Enabled · CopyShelf will launch at your next login.", "사용 중 · 다음 로그인부터 자동으로 실행합니다.")
        case .requiresApproval:
            loginButton.state = .mixed
            loginStatus.stringValue = L("Approval needed. Allow CopyShelf in macOS Login Items settings.", "macOS 승인이 필요합니다. 로그인 항목 설정에서 CopyShelf를 허용해 주세요.")
        case .disabled:
            loginButton.state = .off
            loginStatus.stringValue = L("Off · Open CopyShelf yourself to start recording.", "꺼짐 · CopyShelf를 직접 실행하면 기록을 시작합니다.")
        case .unavailable:
            loginButton.state = .off
            loginStatus.stringValue = L("Unavailable. Use the built CopyShelf.app and check Login Items settings.", "자동 실행 상태를 확인할 수 없습니다. 빌드한 CopyShelf.app과 로그인 항목 설정을 확인해 주세요.")
        }
        if loginItem.demo { loginStatus.stringValue = L("Preview mode · These settings cannot be changed.", "미리보기에서는 설정을 변경하지 않습니다.") }
        else if let lastError { loginStatus.stringValue = lastError }
    }

    func windowDidBecomeKey(_ notification: Notification) { refresh(clearError: true) }
    func windowDidResignKey(_ notification: Notification) { cancelShortcutRecording() }
    func windowWillClose(_ notification: Notification) { cancelShortcutRecording() }

    @objc private func recordShortcut() {
        guard !loginItem.demo, shortcutMonitor == nil else { return }
        shortcutButton.title = L("Press keys…", "키 조합을 누르세요…")
        shortcutStatus.stringValue = L("Press your shortcut. Escape cancels.", "원하는 단축키를 누르세요. Esc로 취소합니다.")
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                self.cancelShortcutRecording()
                return nil
            }
            self.cancelShortcutRecording()
            guard let value = KeyboardShortcut(event: event) else {
                self.shortcutStatus.stringValue = HotKeyController.ChangeError.invalid.localizedDescription
                return nil
            }
            do {
                try self.setShortcut(value)
                self.shortcutButton.title = self.shortcut().display
                self.shortcutStatus.stringValue = L("Shortcut saved.", "단축키를 저장했습니다.")
            } catch { self.shortcutStatus.stringValue = error.localizedDescription }
            return nil
        }
    }
    private func cancelShortcutRecording() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        shortcutButton.title = shortcut().display
        shortcutStatus.stringValue = L("Click the shortcut to change it. Include Command or Control.", "단축키를 클릭해 변경합니다. ⌘ 또는 ⌃를 포함해 주세요.")
    }

    @objc private func changeRecording() { setRecording(recordingButton.state == .on); refresh() }
    @objc private func changeLoginItem() {
        do {
            try loginItem.setEnabled(!loginItem.state.isRegistered)
            lastError = nil
        } catch {
            lastError = L("Could not change launch at login. Check Login Items settings. ", "자동 실행 설정을 바꾸지 못했습니다. 로그인 항목 설정을 확인해 주세요. ") + error.localizedDescription
        }
        refresh()
    }
    @objc private func openPasteSettings() { PasteService.openAccessibilitySettings() }
    @objc private func clearHistory() {
        guard !loginItem.demo, let window else { return }
        let alert = NSAlert()
        alert.messageText = L("Clear all saved history?", "저장한 기록을 모두 지울까요?")
        alert.informativeText = L("Saved text and images will be removed. The current clipboard stays available.", "저장한 텍스트와 이미지를 지웁니다. 현재 클립보드 내용은 유지됩니다.")
        alert.addButton(withTitle: L("Clear history", "기록 지우기"))
        alert.addButton(withTitle: L("Cancel", "취소"))
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.onClear() }
        }
    }
    @objc private func openSystemSettings() { lastError = nil; loginItem.openSettings() }
}
