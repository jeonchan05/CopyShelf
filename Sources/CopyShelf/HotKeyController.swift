import Carbon
import Foundation

protocol HotKeyService: AnyObject {
    // A failed replacement must leave the previous registration effective.
    func register(_ shortcut: KeyboardShortcut) -> OSStatus
}

@MainActor
final class HotKeyController {
    enum ChangeError: LocalizedError {
        case invalid, unavailable, preview
        var errorDescription: String? {
            switch self {
            case .invalid: return L("Include Command or Control. Command-V is reserved for pasting.", "⌘ 또는 ⌃를 포함해 주세요. ⌘V는 붙여넣기에 사용합니다.")
            case .unavailable: return L("This shortcut could not be registered. Try another combination; your previous shortcut is unchanged.", "단축키를 등록하지 못했습니다. 다른 조합을 선택해 주세요. 기존 단축키는 유지됩니다.")
            case .preview: return L("Settings cannot be changed in preview mode.", "미리보기에서는 설정을 변경하지 않습니다.")
            }
        }
    }
    private let preferences: AppPreferences
    private let service: HotKeyService
    private let demo: Bool
    var shortcut: KeyboardShortcut { preferences.shortcut }

    init(preferences: AppPreferences, service: HotKeyService, demo: Bool) {
        self.preferences = preferences; self.service = service; self.demo = demo
    }
    func start() -> OSStatus { demo ? noErr : service.register(shortcut) }
    func setShortcut(_ candidate: KeyboardShortcut) throws {
        guard !demo else { throw ChangeError.preview }
        guard candidate.isValid else { throw ChangeError.invalid }
        guard service.register(candidate) == noErr else { throw ChangeError.unavailable }
        preferences.shortcut = candidate
    }
}
