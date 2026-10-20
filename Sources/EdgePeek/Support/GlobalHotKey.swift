import Carbon
import Foundation

@MainActor
final class GlobalHotKey {
    enum Shortcut: UInt32 {
        case newNote = 1, allNotes = 2
        var modifiers: UInt32 {
            self == .newNote ? UInt32(cmdKey | shiftKey) : UInt32(controlKey | optionKey)
        }
    }

    private static let signature: OSType = 0x4544504B // EDPK
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let shortcut: Shortcut
    private let action: () -> Void

    init?(
        shortcut: Shortcut = .newNote,
        action: @escaping () -> Void
    ) {
        self.action = action
        self.shortcut = shortcut

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                guard GlobalHotKey.shortcut(in: event) == manager.shortcut else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async {
                    manager.fire()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: shortcut.rawValue
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            return nil
        }
    }

    private func fire() {
        action()
    }

    static func shortcut(in event: EventRef) -> Shortcut? {
        guard GetEventClass(event) == OSType(kEventClassKeyboard),
              GetEventKind(event) == UInt32(kEventHotKeyPressed) else { return nil }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &identifier)
        guard status == noErr, identifier.signature == signature else { return nil }
        return Shortcut(rawValue: identifier.id)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
