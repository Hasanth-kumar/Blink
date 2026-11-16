import AppKit
import Combine
import CoreServices

/// Wires the scheduler to the menu bar, the heads-up, the break screen and the
/// Settings window, and handles everything that arrives from outside the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let scheduler = BreakScheduler.shared

    private var statusItemController: StatusItemController?
    private var headsUpController: HeadsUpController?
    private var overlayController: BreakOverlayController?
    private var nudgeController: NudgeController?
    private let settingsWindowController = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)

        let statusItemController = StatusItemController(scheduler: scheduler, settings: settings)
        statusItemController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        self.statusItemController = statusItemController

        headsUpController = HeadsUpController(scheduler: scheduler, settings: settings)
        let overlayController = BreakOverlayController(scheduler: scheduler, settings: settings)
        self.overlayController = overlayController
        let nudgeController = NudgeController(settings: settings)
        self.nudgeController = nudgeController

        // Hooks the Settings UI can call without knowing who answers.
        let actions = AppActions.shared
        actions.previewBreakScreen = { [weak overlayController] in
            overlayController?.showPreview()
        }
        actions.previewNudge = { [weak nudgeController] kind in
            nudgeController?.show(kind)
        }
        actions.openSettings = { [weak self] in
            self?.showSettings()
        }

        observeSettings()
        observeNudges()

        scheduler.start()
        syncFocusFilter()

        if !settings.hasLaunchedBefore {
            // A menu bar app is easy to miss on first run; open Settings once to say hello.
            settings.hasLaunchedBefore = true
            showSettings()
        } else if AppDelegate.wasOpenedByHand {
            // Opening Blink from Finder, Launchpad, Spotlight or the Dock should show something,
            // as it would for any other app. A start at login stays quiet.
            showSettings()
        }
    }

    /// True when someone opened the app themselves, rather than macOS starting it at login
    /// or a `blink://` link waking it up.
    private static var wasOpenedByHand: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        let launchKind = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        return launchKind != OSType(keyAELaunchedAsLogInItem)
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler.persist()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon (when it is shown) or re-opening the app shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: URL scheme  (blink://break, blink://pause?minutes=30, blink://resume, blink://skip, blink://settings)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "blink" else { return }
        let command = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch command {
        case "break":
            scheduler.startBreakNow()
        case "skip":
            scheduler.skip()
        case "pause":
            let minutesText = items.first(where: { $0.name == "minutes" })?.value ?? ""
            if let minutes = Int(minutesText), minutes > 0 {
                scheduler.pause(.minutes(minutes))
            } else {
                scheduler.pause(.indefinitely)
            }
        case "resume":
            scheduler.resume()
        case "settings":
            showSettings()
        default:
            NSLog("Blink: unknown URL command %@", command)
        }
    }

    // MARK: Settings window

    @objc private func showSettingsFromMenu(_ sender: Any?) {
        showSettings()
    }

    private func showSettings() {
        settingsWindowController.show()
    }

    // MARK: Reacting to settings

    private func observeSettings() {
        // `@Published` publishes just before the value changes, and hands over the new value.
        settings.$showInDock
            .dropFirst()
            .sink { showInDock in
                NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
            }
            .store(in: &cancellables)

        settings.$hotKeyStartBreak
            .sink { [weak self] hotKey in
                self?.register(hotKey, for: .startBreak)
            }
            .store(in: &cancellables)

        settings.$hotKeySkipBreak
            .sink { [weak self] hotKey in
                self?.register(hotKey, for: .skipBreak)
            }
            .store(in: &cancellables)

        settings.$hotKeyTogglePause
            .sink { [weak self] hotKey in
                self?.register(hotKey, for: .togglePause)
            }
            .store(in: &cancellables)
    }

    private func register(_ hotKey: HotKey?, for action: HotKeyAction) {
        guard let hotKey = hotKey else {
            HotKeyCenter.shared.unregister(id: action.carbonID)
            return
        }
        HotKeyCenter.shared.register(id: action.carbonID, hotKey: hotKey) { [weak self] in
            self?.trigger(action)
        }
    }

    private func trigger(_ action: HotKeyAction) {
        switch action {
        case .startBreak:
            scheduler.startBreakNow()
        case .skipBreak:
            scheduler.skip()
        case .togglePause:
            scheduler.togglePause()
        }
    }

    private func observeNudges() {
        scheduler.effects
            .sink { [weak self] effect in
                guard let self = self else { return }
                if case .nudge(let kind) = effect {
                    // Never put a nudge on top of a call, a recording or a full-screen video.
                    if SmartPause.currentReason(settings: self.settings) == nil {
                        self.nudgeController?.show(kind)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Focus

    /// Asks macOS whether a Focus that pauses Blink is already on (for example after a relaunch).
    private func syncFocusFilter() {
        // The filter is only registered in builds made by Xcode, which generates the
        // App Intents metadata. A Command Line Tools build has nothing to ask about.
        guard Bundle.main.url(forResource: "Metadata", withExtension: "appintents") != nil else { return }
        Task {
            guard let filter = try? await BlinkFocusFilter.current else { return }
            let shouldPause = filter.pauseBreaks
            await MainActor.run {
                BreakScheduler.shared.setFocusPause(shouldPause)
            }
        }
    }

    // MARK: Main menu

    /// Blink has no visible menu bar of its own, but text fields in Settings still rely
    /// on a main menu for ⌘C, ⌘V, ⌘W and friends.
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(showSettingsFromMenu(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Blink", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Blink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}
