import AppKit
import Carbon
import ClipboardCore
import Foundation

/// Owns app flows and connects controllers to services.
@MainActor
final class AppCoordinator: NSObject {
    private var statusItem: NSStatusItem!
    private var store: HistoryStore!
    private var historyPanel: HistoryPanel!
    private var monitor: ClipboardMonitor!
    private var hotKey: GlobalHotKey!
    private var shortcutController: HotKeyController!
    private var settingsController: SettingsWindowController?
    private let preferences = AppPreferences()
    private var loginItem: LoginItemController!
    private let pasteService = PasteService()
    private var previousApp: NSRunningApplication?
    private var recording = false
    private var accessBlocked = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var captureSuspensions = Set<String>()
    private let demo = CommandLine.arguments.contains("--demo")

    func prepare() { observeWorkspace() }

    func start() {
        NSApp.setActivationPolicy(.accessory)
        makeMainMenu()
        loginItem = LoginItemController(demo: demo)
        store = HistoryStore(demo: demo)
        historyPanel = HistoryPanel(store: store)
        monitor = ClipboardMonitor()
        monitor.onClip = { [weak self] clip in self?.store.record(clip) }
        monitor.onSkippedImage = { [weak self] in
            self?.historyPanel.showError(L("Image skipped. It may be too large or unsupported.", "이미지를 기록하지 못했습니다. 크기가 너무 크거나 지원하지 않는 형식일 수 있습니다."))
        }
        monitor.onAccessIssue = { [weak self] blocked in
            guard let self, self.accessBlocked != blocked else { return }
            self.accessBlocked = blocked
            self.updateStatus()
        }
        monitor.setSuspended(!captureSuspensions.isEmpty)
        store.onChange = { [weak self] in self?.historyPanel.refresh(); self?.updateStatus() }
        store.onError = { [weak self] message in self?.historyPanel.showError(message) }
        historyPanel.onSettings = { [weak self] in self?.openSettings() }
        historyPanel.onDismiss = { [weak self] in
            _ = self?.previousApp?.activate(options: [.activateIgnoringOtherApps])
        }
        historyPanel.onPaste = { [weak self] clip in self?.paste(clip) }
        historyPanel.onCopy = { [weak self] clip in
            self?.pasteService.cancelPendingPaste()
            do {
                let count = try ClipboardWriter.write(clip)
                self?.monitor.acknowledgeOwnWrite(changeCount: count)
            } catch {
                self?.showAlert(L("Could not copy item", "항목을 복사하지 못했습니다"),
                                L("The clipboard changed or could not accept this item. Try again.", "클립보드가 바뀌었거나 항목을 복사할 수 없습니다. 다시 시도해 주세요."))
            }
        }
        pasteService.didWriteClipboard = { [weak self] count in self?.monitor.acknowledgeOwnWrite(changeCount: count) }
        makeMenuBarItem()
        hotKey = GlobalHotKey { [weak self] in
            MainActor.assumeIsolated { self?.togglePanel() }
        }
        shortcutController = HotKeyController(preferences: preferences, service: hotKey, demo: demo)
        let status = shortcutController.start()
        if status != noErr {
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(L("Shortcut unavailable", "단축키를 등록할 수 없습니다"),
                                L("The shortcut could not be registered. Open CopyShelf from the menu bar and choose another shortcut in Settings.", "단축키를 등록하지 못했습니다. 메뉴 막대에서 CopyShelf를 열고 설정에서 다른 단축키를 선택해 주세요."))
            }
        }
        recording = preferences.shouldRecord(demo: demo)
        if recording { monitor.start() }
        updateStatus()
        if demo || !preferences.hasSeenAutomaticRecording || !preferences.hasLaunched {
            if !demo {
                preferences.hasSeenAutomaticRecording = true
                preferences.hasLaunched = true
            }
            showPanel()
        }
    }

    private func makeMainMenu() {
        let main = NSMenu()
        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let settings = appMenu.addItem(withTitle: L("Settings…", "설정…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quit CopyShelf", "CopyShelf 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: L("Edit", "편집"))
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: L("Cut", "오려두기"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy", "복사"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste", "붙여넣기"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All", "전체 선택"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    private func makeMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CopyShelf")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "CopyShelf · \(preferences.shortcut.display)"
            button.target = self
            button.action = #selector(statusClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = menu.addItem(withTitle: L("Open CopyShelf", "CopyShelf 열기"), action: #selector(openPanel), keyEquivalent: "")
            open.target = self
            menu.addItem(.separator())
            let pause = menu.addItem(withTitle: recording ? L("Pause recording", "기록 일시 정지") : L("Start recording", "기록 시작"), action: #selector(toggleRecording), keyEquivalent: "")
            pause.target = self
            pause.isEnabled = !demo
            let settings = menu.addItem(withTitle: L("Settings…", "설정…"), action: #selector(openSettings), keyEquivalent: "")
            settings.target = self
            menu.addItem(.separator())
            let about = menu.addItem(withTitle: L("About CopyShelf", "CopyShelf 정보"), action: #selector(aboutApp), keyEquivalent: "")
            about.target = self
            let quit = menu.addItem(withTitle: L("Quit CopyShelf", "CopyShelf 종료"), action: #selector(quitApp), keyEquivalent: "q")
            quit.target = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { togglePanel() }
    }

    @objc private func openPanel() { showPanel() }
    private func togglePanel() {
        if historyPanel.panel.isVisible { historyPanel.dismiss() }
        else { showPanel() }
    }
    private func showPanel() {
        pasteService.cancelPendingPaste()
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = app }
        historyPanel.show()
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, String, Bool)] = [
            (NSWorkspace.willSleepNotification, "sleep", true),
            (NSWorkspace.didWakeNotification, "sleep", false),
            (NSWorkspace.screensDidSleepNotification, "display", true),
            (NSWorkspace.screensDidWakeNotification, "display", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session", false)
        ]
        for (name, reason, suspend) in events {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if suspend { self.captureSuspensions.insert(reason) }
                    else { self.captureSuspensions.remove(reason) }
                    self.monitor?.setSuspended(!self.captureSuspensions.isEmpty)
                }
            })
        }
    }

    @objc private func toggleRecording() {
        setRecording(!recording)
    }
    private func setRecording(_ enabled: Bool) {
        guard !demo else { return }
        recording = enabled
        preferences.recordingEnabled = enabled
        if recording { monitor.start() } else { monitor.stop() }
        updateStatus()
        settingsController?.refresh()
    }
    private func updateStatus() {
        historyPanel.updateStatus(recording: recording, accessBlocked: accessBlocked, demo: demo)
    }

    @objc private func openSettings() {
        pasteService.cancelPendingPaste()
        historyPanel.hide()
        if settingsController == nil {
            settingsController = SettingsWindowController(loginItem: loginItem,
                recording: { [weak self] in self?.recording ?? false },
                setRecording: { [weak self] enabled in self?.setRecording(enabled) },
                onClear: { [weak self] in self?.clearHistory() },
                shortcut: { [weak self] in self?.shortcutController.shortcut ?? .default },
                setShortcut: { [weak self] value in
                    guard let self else { return }
                    try self.shortcutController.setShortcut(value)
                    self.statusItem.button?.toolTip = "CopyShelf · \(value.display)"
                })
        }
        settingsController?.show()
    }

    private func clearHistory() {
        monitor.invalidatePendingCaptures()
        pasteService.cancelPendingPaste()
        store.clear()
    }

    func becameActive() { settingsController?.refresh(clearError: true) }

    private func paste(_ clip: Clip) {
        let target = previousApp
        historyPanel.hide()
        pasteService.paste(clip, into: target) { [weak self] result in
            guard let self else { return }
            switch result {
            case .pasted: break
            case .superseded: break
            case .clipboardUnavailable:
                self.showAlert(L("Could not copy item", "항목을 복사하지 못했습니다"),
                               L("The clipboard could not accept the selected item. Try again.", "선택한 항목을 클립보드에 넣지 못했습니다. 다시 시도해 주세요."))
            case .clipboardChanged:
                self.showAlert(L("Paste cancelled", "붙여넣기를 취소했습니다"),
                               L("The clipboard changed while CopyShelf was waiting. Choose the history item again to paste it.", "붙여넣기를 기다리는 동안 클립보드가 바뀌었습니다. 원하는 기록을 다시 선택해 주세요."))
            case .permissionRequired:
                self.showPastePermissionAlert()
            case .copiedOnly:
                self.showAlert(L("Item copied", "항목을 복사했습니다"),
                               L("Automatic paste is unavailable in this field. Click the destination and press Command-V.", "이 입력란에서는 자동 붙여넣기를 사용할 수 없습니다. 입력할 곳을 클릭한 뒤 ⌘V를 눌러 주세요."))
            case .targetUnavailable:
                self.showAlert(L("Item copied", "항목을 복사했습니다"),
                               L("The previous app could not receive a paste. Click its text field and press Command-V.", "이전 앱에 자동으로 붙여넣을 수 없습니다. 입력할 곳을 클릭한 뒤 ⌘V를 눌러 주세요."))
            }
        }
    }

    private func showPastePermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Item copied. Enable automatic paste?", "복사했습니다. 자동 붙여넣기를 허용할까요?")
        alert.informativeText = L("CopyShelf needs Accessibility access to send Command-V to your previous app. You can also paste this item yourself with Command-V.", "CopyShelf가 이전 앱에 ⌘V를 보내려면 손쉬운 사용 권한이 필요합니다. 지금은 ⌘V로 직접 붙여넣을 수 있습니다.")
        alert.addButton(withTitle: L("Open System Settings", "시스템 설정 열기"))
        alert.addButton(withTitle: L("Keep manual paste", "직접 붙여넣기"))
        if alert.runModal() == .alertFirstButtonReturn { PasteService.openAccessibilitySettings() }
        else { _ = previousApp?.activate(options: [.activateIgnoringOtherApps]) }
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func aboutApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "CopyShelf",
            .applicationVersion: Foundation.Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.1",
            .credits: NSAttributedString(string: L("A small clipboard history for your Mac.\nChoose your shortcut in Settings. Arrow keys to choose. Enter to paste.", "Mac을 위한 작은 클립보드 기록 앱.\n설정에서 단축키를 바꾸고, 방향키로 선택하고, Enter로 붙여넣으세요."))])
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func reopen(hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showPanel() }
        return true
    }
    func stop() {
        monitor.stop(); pasteService.cancelPendingPaste(); store.finishWrites()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
