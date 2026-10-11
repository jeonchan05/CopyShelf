import AppKit
import ApplicationServices
import Carbon
import ClipboardCore

@MainActor
final class PasteService {
    enum Result { case pasted, permissionRequired, copiedOnly, targetUnavailable, clipboardChanged, clipboardUnavailable, superseded }
    var didWriteClipboard: ((Int) -> Void)?
    private var activeAttempt: UUID?

    func cancelPendingPaste() { activeAttempt = nil }

    func paste(_ clip: Clip, into target: NSRunningApplication?, completion: @escaping (Result) -> Void) {
        cancelPendingPaste()
        let board = NSPasteboard.general
        let changeCount: Int
        do { changeCount = try ClipboardWriter.write(clip, to: board) }
        catch ClipboardWriter.WriteError.changed { completion(.clipboardChanged); return }
        catch { completion(.clipboardUnavailable); return }
        didWriteClipboard?(changeCount)
        // Use the generation returned by our own write, not a later clipboard read.
        let attempt = PasteAttempt(clipboardChangeCount: changeCount)
        activeAttempt = attempt.id
        guard attempt.clipboardIsUnchanged(board.changeCount) else {
            activeAttempt = nil
            completion(.clipboardChanged)
            return
        }
        guard let target, !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            completion(.targetUnavailable)
            return
        }
        guard AXIsProcessTrusted() else {
            _ = target.activate(options: [.activateIgnoringOtherApps])
            completion(.permissionRequired)
            return
        }
        guard !IsSecureEventInputEnabled() else {
            _ = target.activate(options: [.activateIgnoringOtherApps])
            completion(.copiedOnly)
            return
        }
        _ = target.activate(options: [.activateIgnoringOtherApps])
        waitForFocus(target, attempt: attempt, attempts: 20, completion: completion)
    }

    private func waitForFocus(_ target: NSRunningApplication, attempt: PasteAttempt,
                              attempts: Int, completion: @escaping (Result) -> Void) {
        guard attempt.isCurrent(activeAttempt) else { completion(.superseded); return }
        guard attempt.clipboardIsUnchanged(NSPasteboard.general.changeCount) else {
            activeAttempt = nil
            completion(.clipboardChanged)
            return
        }
        guard !target.isTerminated else { completion(.targetUnavailable); return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
            // Give the destination time to restore its field editor after activation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, attempt.isCurrent(self.activeAttempt) else { completion(.superseded); return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                      !target.isTerminated, !IsSecureEventInputEnabled(), AXIsProcessTrusted(),
                      !Self.focusedFieldIsSecure(in: target),
                      let source = CGEventSource(stateID: .combinedSessionState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                    completion(.copiedOnly)
                    return
                }
                // Focus checks can take time. Check the clipboard again immediately before sending keys.
                guard attempt.clipboardIsUnchanged(NSPasteboard.general.changeCount) else {
                    self.activeAttempt = nil
                    completion(.clipboardChanged)
                    return
                }
                guard attempt.isCurrent(self.activeAttempt),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                      !target.isTerminated, !IsSecureEventInputEnabled(), AXIsProcessTrusted() else {
                    completion(.copiedOnly)
                    return
                }
                self.activeAttempt = nil
                down.flags = .maskCommand
                up.flags = .maskCommand
                down.postToPid(target.processIdentifier)
                up.postToPid(target.processIdentifier)
                completion(.pasted)
            }
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.waitForFocus(target, attempt: attempt, attempts: attempts - 1, completion: completion)
            }
        } else { completion(.targetUnavailable) }
    }

    private static func focusedFieldIsSecure(in target: NSRunningApplication) -> Bool {
        let application = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success else { return false }
        return subrole as? String == kAXSecureTextFieldSubrole as String
    }

    static func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
