import AppKit
import Carbon

struct KeyboardShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let `default` = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey))
    private static let allowedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    var isValid: Bool {
        guard keyCode <= 126, !(54...63).contains(keyCode),
              modifiers & Self.allowedModifiers == modifiers,
              modifiers & UInt32(cmdKey | controlKey) != 0 else { return false }
        // CopyShelf sends Command-V to paste; claiming it would intercept its own paste.
        return !(keyCode == UInt32(kVK_ANSI_V) && modifiers == UInt32(cmdKey))
    }

    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }

    init?(event: NSEvent) {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        if !isValid { return nil }
    }

    var display: String {
        var symbols = ""
        for (mask, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(mask) != 0 { symbols += symbol }
        }
        let keys: [UInt32: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B",
            12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6", 23:"5",
            24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0", 30:"]", 31:"O", 32:"U", 33:"[", 34:"I", 35:"P",
            36:"↩", 37:"L", 38:"J", 39:"'", 40:"K", 41:";", 42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".",
            48:"⇥", 49:"Space", 50:"`", 51:"⌫", 53:"⎋", 64:"F17", 65:"Num .", 67:"Num *", 69:"Num +",
            71:"Clear", 75:"Num /", 76:"Num ↩", 78:"Num -", 79:"F18", 80:"F19", 81:"Num =",
            82:"Num 0", 83:"Num 1", 84:"Num 2", 85:"Num 3", 86:"Num 4", 87:"Num 5", 88:"Num 6",
            89:"Num 7", 90:"F20", 91:"Num 8", 92:"Num 9", 96:"F5", 97:"F6", 98:"F7", 99:"F3",
            100:"F8", 101:"F9", 103:"F11", 105:"F13", 106:"F16", 107:"F14", 109:"F10", 111:"F12",
            114:"Help", 115:"Home", 116:"Page Up", 117:"⌦", 118:"F4", 119:"End", 120:"F2",
            121:"Page Down", 122:"F1", 123:"←", 124:"→", 125:"↓", 126:"↑"
        ]
        return symbols + (keys[keyCode] ?? "Key \(keyCode)")
    }
}
