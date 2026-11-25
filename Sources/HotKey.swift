import Carbon.HIToolbox

/// Global shortcut through Carbon, which needs no Accessibility permission.
final class HotKey {
    private static var nextID: UInt32 = 1

    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let id: UInt32
    private let handler: () -> Void

    init(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        self.handler = handler
        id = Self.nextID
        Self.nextID += 1
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        // Every registered key reaches every handler, so each one checks the id first.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard pressed.id == me.id else { return OSStatus(eventNotHandledErr) }
            me.handler()
            return noErr
        }, 1, &spec, me, &handlerRef)
        let hotKeyID = EventHotKeyID(signature: OSType(0x5050_4C52), id: id) // "PPLR"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
