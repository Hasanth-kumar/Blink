import AppKit
import SwiftUI

/// Owns the Settings window. A plain `NSWindow` hosting SwiftUI is used (rather than a
/// SwiftUI `Settings` scene) because it can be opened reliably from a menu bar app.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let uiState = SettingsUIState()

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView()
            .environmentObject(AppSettings.shared)
            .environmentObject(StatsStore.shared)
            .environmentObject(LaunchAtLogin.shared)
            .environmentObject(BreakScheduler.shared)
            .environmentObject(uiState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Blink Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.setContentSize(NSSize(width: 820, height: 580))
        window.center()
        window.setFrameAutosaveName("BlinkSettingsWindow")
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Login-item approval may have changed while the window was open.
        LaunchAtLogin.shared.refresh()
    }
}
