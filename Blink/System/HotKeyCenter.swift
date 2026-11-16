import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts, registered through Carbon's hot-key API.
///
/// This API works without Accessibility permission, which is why it is used here
/// instead of an event tap.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Registration {
        var hotKey: HotKey
        var handler: () -> Void
        var reference: EventHotKeyRef?
    }

    /// 'BLNK'
    private let signature: OSType = 0x424C_4E4B
    private var registrations: [UInt32: Registration] = [:]
    private var eventHandler: EventHandlerRef?
    private var isSuspended = false

    private init() {
        installEventHandler()
    }

    /// Registers (or replaces) the shortcut stored under `id`.
    func register(id: UInt32, hotKey: HotKey, handler: @escaping () -> Void) {
        unregister(id: id)
        var registration = Registration(hotKey: hotKey, handler: handler, reference: nil)
        if !isSuspended {
            registration.reference = makeReference(id: id, hotKey: hotKey)
        }
        registrations[id] = registration
    }

    func unregister(id: UInt32) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        if let reference = registration.reference {
            _ = UnregisterEventHotKey(reference)
        }
    }

    /// Temporarily releases every shortcut, so the recorder in Settings can capture
    /// a key combination that is already in use.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        for id in Array(registrations.keys) {
            if let reference = registrations[id]?.reference {
                _ = UnregisterEventHotKey(reference)
            }
            registrations[id]?.reference = nil
        }
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        for id in Array(registrations.keys) {
            if let hotKey = registrations[id]?.hotKey {
                registrations[id]?.reference = makeReference(id: id, hotKey: hotKey)
            }
        }
    }

    // MARK: Carbon plumbing

    private func makeReference(id: UInt32, hotKey: HotKey) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status != 0 {
            NSLog("Blink: could not register shortcut %@ (error %d)", hotKey.display, Int32(status))
            return nil
        }
        return reference
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // A C callback cannot capture anything, so it reaches the center through `shared`.
        let callback: EventHandlerUPP = { _, event, _ in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == 0 else { return status }
            HotKeyCenter.shared.fire(id: hotKeyID.id)
            return 0
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandler)
        if status != 0 {
            NSLog("Blink: could not install the shortcut handler (error %d)", Int32(status))
        }
    }

    private func fire(id: UInt32) {
        guard !isSuspended, let registration = registrations[id] else { return }
        registration.handler()
    }
}
