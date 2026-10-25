import Carbon

// Carbon hot keys work system-wide without Accessibility permission.
@MainActor
final class HotKeys {
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init() throws {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKeys.actions[id.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw AppError.message("Keyboard shortcuts could not be set up (error \(status)).") }
    }

    func register(_ name: String, keyCode: Int, action: @escaping () -> Void) throws {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(optionKey | shiftKey),
                                         EventHotKeyID(signature: OSType(0x42554243), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            throw AppError.message("The \(name) shortcut could not be set. Another app may already use it.")
        }
        actions[id] = action
        refs.append(ref)
    }
}
