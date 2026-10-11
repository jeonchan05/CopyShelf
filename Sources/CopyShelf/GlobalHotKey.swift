import Carbon

final class GlobalHotKey: HotKeyService {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var currentID: UInt32 = 0
    private var currentShortcut: KeyboardShortcut?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    func register(_ shortcut: KeyboardShortcut = .default) -> OSStatus {
        guard shortcut.isValid else { return OSStatus(paramErr) }
        if reference != nil, shortcut == currentShortcut { return noErr }
        if handler == nil {
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                guard result == noErr, id.signature == 0x43534846, id.id == owner.currentID else {
                    return OSStatus(eventNotHandledErr)
                }
                owner.action()
                return noErr
            }, 1, &spec, pointer, &handler)
            guard status == noErr else { return status }
        }
        let nextID = currentID == UInt32.max ? 1 : currentID + 1
        let id = EventHotKeyID(signature: 0x43534846, id: nextID)
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                        GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr, let candidate else { return status == noErr ? OSStatus(paramErr) : status }
        let previous = reference
        reference = candidate
        currentID = nextID
        currentShortcut = shortcut
        if let previous { UnregisterEventHotKey(previous) }
        return noErr
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
