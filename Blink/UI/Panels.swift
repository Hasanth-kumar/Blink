import AppKit
import SwiftUI

/// A borderless panel that can take keyboard focus without activating the app.
/// Used for the break screen, so Esc works while the user's own app stays "active".
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A borderless panel that never takes keyboard focus. Used for the heads-up and nudges,
/// so they can appear mid-sentence without swallowing a single keystroke.
final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A hosting view whose buttons respond to the first click even though its window is not key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSPanel {
    /// Shared setup for Blink's floating surfaces: transparent, on every Space,
    /// above full-screen apps, and never hidden just because Blink is not the active app.
    func configureAsOverlay(level: NSWindow.Level) {
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
    }
}

extension NSScreen {
    /// The display the pointer is on, which is where the user is most likely looking.
    static var withPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        for screen in screens where NSMouseInRect(location, screen.frame, false) {
            return screen
        }
        return main ?? screens.first
    }
}

enum Motion {
    /// True when the user has asked macOS to reduce motion.
    @MainActor
    static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
