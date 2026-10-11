import AppKit
import Carbon
import Foundation
import Testing
@testable import CopyShelf

@MainActor
struct ShortcutTests {
    private final class Service: HotKeyService {
        var result: OSStatus = noErr
        var current: KeyboardShortcut?
        var calls = 0
        func register(_ shortcut: KeyboardShortcut) -> OSStatus {
            calls += 1
            if result == noErr { current = shortcut }
            return result
        }
    }
    private func preferences() -> (AppPreferences, UserDefaults, String) {
        let name = "CopyShelf-shortcut-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (AppPreferences(defaults: defaults), defaults, name)
    }

    @Test func shortcutIsSavedAndRegisteredAgainAfterRestart() throws {
        let (preferences, defaults, name) = preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = Service()
        let controller = HotKeyController(preferences: preferences, service: service, demo: false)
        #expect(controller.start() == noErr)
        #expect(service.current == .default)
        let chosen = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | optionKey))
        try controller.setShortcut(chosen)
        let restarted = HotKeyController(preferences: AppPreferences(defaults: defaults), service: service, demo: false)
        #expect(restarted.shortcut == chosen)
        #expect(restarted.start() == noErr)
        #expect(service.current == chosen)
        #expect(chosen.display == "⌃⌥B")
    }

    @Test func conflictPreservesThePreviousPreferenceAndRegistration() throws {
        let (preferences, defaults, name) = preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = Service()
        let controller = HotKeyController(preferences: preferences, service: service, demo: false)
        #expect(controller.start() == noErr)
        service.result = OSStatus(eventHotKeyExistsErr)
        let chosen = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | shiftKey))
        #expect(throws: HotKeyController.ChangeError.self) { try controller.setShortcut(chosen) }
        #expect(controller.shortcut == .default)
        #expect(service.current == .default)
        #expect(defaults.object(forKey: "historyShortcut") == nil)
    }

    @Test func unmodifiedKeysAndPasteShortcutNeverReachRegistration() {
        let (preferences, defaults, name) = preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = Service()
        let controller = HotKeyController(preferences: preferences, service: service, demo: false)
        for chosen in [KeyboardShortcut(keyCode: 9, modifiers: 0), KeyboardShortcut(keyCode: 9, modifiers: UInt32(cmdKey)),
                       KeyboardShortcut(keyCode: 9, modifiers: UInt32(shiftKey)), KeyboardShortcut(keyCode: 55, modifiers: UInt32(cmdKey)),
                       KeyboardShortcut(keyCode: 500, modifiers: UInt32(cmdKey))] {
            #expect(!chosen.isValid)
            #expect(throws: HotKeyController.ChangeError.self) { try controller.setShortcut(chosen) }
        }
        #expect(service.calls == 0)
        #expect(controller.shortcut == .default)
    }

    @Test func corruptAndUnsupportedSavedShortcutsUseTheDefault() throws {
        let (preferences, defaults, name) = preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("broken".utf8), forKey: "historyShortcut")
        #expect(preferences.shortcut == .default)
        let unsafe = KeyboardShortcut(keyCode: 9, modifiers: UInt32(cmdKey))
        defaults.set(try JSONEncoder().encode(unsafe), forKey: "historyShortcut")
        #expect(preferences.shortcut == .default)
    }

    @Test func previewCannotRegisterOrSaveAShortcut() {
        let (preferences, defaults, name) = preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = Service()
        let controller = HotKeyController(preferences: preferences, service: service, demo: true)
        #expect(controller.start() == noErr)
        #expect(throws: HotKeyController.ChangeError.self) { try controller.setShortcut(.default) }
        #expect(service.calls == 0)
        #expect(defaults.object(forKey: "historyShortcut") == nil)
    }

    @Test func recordedEventsIgnoreCapsLockAndFunctionFlags() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .option, .capsLock, .function], timestamp: 0, windowNumber: 0,
            context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: UInt16(kVK_ANSI_V)))
        #expect(KeyboardShortcut(event: event) == .default)
    }
}
