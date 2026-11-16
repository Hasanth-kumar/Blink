import AppKit

/// A button that records the next key combination pressed while it is armed.
/// Wrapped for SwiftUI by `ShortcutRecorder`.
final class RecorderButton: NSButton {
    var hotKey: HotKey? {
        didSet { refreshTitle() }
    }
    var onChange: (HotKey?) -> Void = { _ in }

    private var isRecording = false
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording(_:))
        refreshTitle()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, isRecording {
            stopRecording()
        }
    }

    @objc private func toggleRecording(_ sender: Any?) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        // Release Blink's own shortcuts so an existing combination can be re-recorded.
        HotKeyCenter.shared.suspend()
        refreshTitle()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            self.handle(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        HotKeyCenter.shared.resume()
        refreshTitle()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)
        let hasMainModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)

        if keyCode == Key.escape, !hasMainModifier {
            stopRecording()
            return
        }
        if keyCode == Key.delete || keyCode == Key.forwardDelete, !hasMainModifier {
            stopRecording()
            hotKey = nil
            onChange(nil)
            return
        }

        let isFunctionKey = RecorderButton.functionKeyNames[keyCode] != nil
        guard hasMainModifier || isFunctionKey else {
            NSSound.beep()
            return
        }

        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= CarbonModifier.command }
        if flags.contains(.option) { carbonModifiers |= CarbonModifier.option }
        if flags.contains(.control) { carbonModifiers |= CarbonModifier.control }
        if flags.contains(.shift) { carbonModifiers |= CarbonModifier.shift }

        let recorded = HotKey(
            keyCode: UInt32(keyCode),
            modifiers: carbonModifiers,
            display: RecorderButton.describe(flags: flags, keyCode: keyCode, characters: event.charactersIgnoringModifiers)
        )
        stopRecording()
        hotKey = recorded
        onChange(recorded)
    }

    private func refreshTitle() {
        if isRecording {
            title = "Press shortcut…"
        } else if let hotKey = hotKey {
            title = hotKey.display
        } else {
            title = "Record Shortcut"
        }
    }

    // MARK: Key names

    /// Virtual key codes for the keys that have no printable character.
    private enum Key {
        static let returnKey = 36
        static let tab = 48
        static let space = 49
        static let delete = 51
        static let escape = 53
        static let forwardDelete = 117
        static let home = 115
        static let end = 119
        static let pageUp = 116
        static let pageDown = 121
        static let leftArrow = 123
        static let rightArrow = 124
        static let downArrow = 125
        static let upArrow = 126
    }

    /// Carbon's modifier masks, which is what the hot-key API expects.
    private enum CarbonModifier {
        static let command: UInt32 = 0x0100
        static let shift: UInt32 = 0x0200
        static let option: UInt32 = 0x0800
        static let control: UInt32 = 0x1000
    }

    /// F1 – F12.
    private static let functionKeyNames: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]

    private static let keyNames: [Int: String] = [
        Key.returnKey: "↩",
        Key.tab: "⇥",
        Key.space: "Space",
        Key.delete: "⌫",
        Key.forwardDelete: "⌦",
        Key.escape: "⎋",
        Key.leftArrow: "←",
        Key.rightArrow: "→",
        Key.downArrow: "↓",
        Key.upArrow: "↑",
        Key.home: "↖",
        Key.end: "↘",
        Key.pageUp: "⇞",
        Key.pageDown: "⇟"
    ]

    private static func describe(flags: NSEvent.ModifierFlags, keyCode: Int, characters: String?) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }

        if let name = keyNames[keyCode] ?? functionKeyNames[keyCode] {
            text += name
        } else if let characters = characters, !characters.isEmpty {
            text += characters.uppercased()
        } else {
            text += "Key \(keyCode)"
        }
        return text
    }
}
