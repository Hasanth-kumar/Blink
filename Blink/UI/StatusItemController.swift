import AppKit
import Combine

/// The menu bar item: an icon, an optional countdown, and the control menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    var onOpenSettings: () -> Void = {}

    private let scheduler: BreakScheduler
    private let settings: AppSettings
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()
    private var currentSymbol = ""

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let takeBreakItem = NSMenuItem(title: "Take a Break Now", action: nil, keyEquivalent: "")
    private let skipItem = NSMenuItem(title: "Skip Next Break", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
    private let resumeItem = NSMenuItem(title: "Resume", action: nil, keyEquivalent: "")

    init(scheduler: BreakScheduler, settings: AppSettings) {
        self.scheduler = scheduler
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.setAccessibilityLabel("Blink")
        }
        buildMenu()
        statusItem.menu = menu

        scheduler.didUpdate
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
        refresh()
    }

    // MARK: Menu

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(NSMenuItem.separator())

        wire(takeBreakItem, to: #selector(takeBreak(_:)))
        menu.addItem(takeBreakItem)

        wire(skipItem, to: #selector(skipBreak(_:)))
        menu.addItem(skipItem)

        menu.addItem(NSMenuItem.separator())

        let pauseMenu = NSMenu()
        pauseMenu.autoenablesItems = false
        pauseMenu.addItem(makeItem("For 15 Minutes", action: #selector(pauseFifteenMinutes(_:))))
        pauseMenu.addItem(makeItem("For 1 Hour", action: #selector(pauseOneHour(_:))))
        pauseMenu.addItem(makeItem("Until Tomorrow", action: #selector(pauseUntilTomorrow(_:))))
        pauseMenu.addItem(NSMenuItem.separator())
        pauseMenu.addItem(makeItem("Indefinitely", action: #selector(pauseIndefinitely(_:))))
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)

        wire(resumeItem, to: #selector(resume(_:)))
        menu.addItem(resumeItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem("Settings…", action: #selector(openSettings(_:)), key: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem("Quit Blink", action: #selector(quit(_:)), key: "q"))
    }

    private func wire(_ item: NSMenuItem, to action: Selector) {
        item.target = self
        item.action = action
    }

    private func makeItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenu()
    }

    private func refreshMenu() {
        statusLine.title = scheduler.statusText()

        let onBreak = scheduler.isOnBreak
        let paused = scheduler.isPaused
        var countingDown = false
        switch scheduler.state {
        case .working, .preBreakWarning, .holding:
            countingDown = true
        case .onBreak, .paused, .idle, .outsideOfficeHours:
            countingDown = false
        }

        takeBreakItem.isEnabled = !onBreak
        skipItem.title = onBreak ? "Skip This Break" : "Skip Next Break"
        skipItem.isEnabled = scheduler.canSkip && (onBreak || countingDown)
        pauseItem.isHidden = paused
        pauseItem.isEnabled = !onBreak
        resumeItem.isHidden = !paused
    }

    // MARK: Title

    private func refresh() {
        refreshMenu()
        guard let button = statusItem.button else { return }

        let now = Date()
        var symbol = "eye"
        var text = ""
        let showsTime = settings.menuBarStyle != .iconOnly

        switch scheduler.state {
        case .working(let deadline):
            if showsTime {
                let remaining = deadline.timeIntervalSince(now)
                if settings.menuBarStyle == .minutes, remaining > 60 {
                    text = TimeFormat.minutes(remaining)
                } else {
                    text = TimeFormat.clock(remaining)
                }
            }
        case .preBreakWarning(let breakAt):
            if showsTime {
                text = TimeFormat.clock(breakAt.timeIntervalSince(now))
            }
        case .holding:
            symbol = "hourglass"
        case .onBreak(_, _, let endsAt):
            symbol = "leaf"
            if showsTime {
                text = TimeFormat.clock(endsAt.timeIntervalSince(now))
            }
        case .paused:
            symbol = "pause.circle"
        case .idle:
            symbol = "moon.zzz"
        case .outsideOfficeHours:
            symbol = "moon.stars"
        }

        if symbol != currentSymbol {
            currentSymbol = symbol
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Blink")
            image?.isTemplate = true
            button.image = image
        }
        let title = text.isEmpty ? "" : " \(text)"
        if button.title != title {
            button.title = title
        }
        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = scheduler.statusText(now: now)
    }

    // MARK: Actions

    @objc private func takeBreak(_ sender: Any?) {
        scheduler.startBreakNow()
    }

    @objc private func skipBreak(_ sender: Any?) {
        scheduler.skip()
    }

    @objc private func pauseFifteenMinutes(_ sender: Any?) {
        scheduler.pause(.minutes(15))
    }

    @objc private func pauseOneHour(_ sender: Any?) {
        scheduler.pause(.minutes(60))
    }

    @objc private func pauseUntilTomorrow(_ sender: Any?) {
        scheduler.pause(.untilTomorrow)
    }

    @objc private func pauseIndefinitely(_ sender: Any?) {
        scheduler.pause(.indefinitely)
    }

    @objc private func resume(_ sender: Any?) {
        scheduler.resume()
    }

    @objc private func openSettings(_ sender: Any?) {
        onOpenSettings()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
