import AppKit
import Combine

enum PauseOption {
    case minutes(Int)
    case untilTomorrow
    case indefinitely
}

/// The single source of truth for "what is Blink doing right now".
///
/// `SchedulerCore` decides; this class gives it a clock, live system readings and
/// persistence, and publishes the result for the menu bar, heads-up and break screen.
@MainActor
final class BreakScheduler: NSObject, ObservableObject {
    static let shared = BreakScheduler()

    @Published private(set) var state: SchedulerState

    /// Fires after every tick or command, once `state` has settled.
    let didUpdate = PassthroughSubject<Void, Never>()
    /// Break started / ended, nudges, snoozes and so on.
    let effects = PassthroughSubject<SchedulerEffect, Never>()
    /// The message chosen for the break that is showing.
    private(set) var currentMessage = ""

    private enum AwayReason: Hashable {
        case systemSleep
        case displaySleep
        case screenLocked
        case screenSaver
        case sessionInactive
    }

    private static let snapshotKey = "schedulerSnapshot"

    private let settings: AppSettings
    private let stats: StatsStore
    private let core: SchedulerCore
    private var timer: Timer?
    private var awayReasons = Set<AwayReason>()
    private var cancellables = Set<AnyCancellable>()
    private var activityToken: NSObjectProtocol?
    private var hasStarted = false
    private var lastMessages: [BreakKind: String] = [:]
    private lazy var probes: SchedulerProbes = makeProbes()

    private override init() {
        let settings = AppSettings.shared
        let core = SchedulerCore(config: settings.scheduleConfig, now: Date())
        self.settings = settings
        self.stats = StatsStore.shared
        self.core = core
        self.state = core.state
        super.init()
    }

    // MARK: Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // A menu bar app with no windows is a prime candidate for App Nap, which would
        // delay its timers. This keeps the timers honest while still letting the Mac sleep.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Keeping break timers accurate"
        )

        restoreSnapshot()
        observeSystemEvents()

        settings.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsDidChange()
            }
            .store(in: &cancellables)

        tick()
    }

    /// Writes the current state to disk. Called on every transition and at quit.
    func persist() {
        saveSnapshot()
    }

    // MARK: Commands

    func startBreakNow() {
        finish(core.startBreakNow(now: Date()))
    }

    func skip() {
        finish(core.skip(now: Date()))
    }

    func snooze(minutes: Int) {
        finish(core.snooze(TimeInterval(max(1, minutes) * 60), now: Date()))
    }

    func pause(_ option: PauseOption) {
        let now = Date()
        let until: Date?
        switch option {
        case .minutes(let minutes):
            until = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        case .untilTomorrow:
            until = startOfNextDay(after: now)
        case .indefinitely:
            until = nil
        }
        finish(core.pause(until: until, now: now))
    }

    func resume() {
        finish(core.resume(now: Date()))
    }

    func togglePause() {
        if case .paused = state {
            resume()
        } else {
            pause(.indefinitely)
        }
    }

    /// Called by the Focus Filter when a Focus that pauses Blink turns on or off.
    func setFocusPause(_ active: Bool) {
        guard active != core.focusPauseActive else { return }
        finish(core.setFocusPause(active, now: Date()))
    }

    // MARK: Read-only values for the UI

    var snoozesRemaining: Int? { core.snoozesRemaining }
    var canSnooze: Bool { core.canSnooze }
    var canSkip: Bool { core.canSkip }
    var nextBreakKind: BreakKind { core.nextBreakKind }
    var warningLength: TimeInterval { core.warningLength }

    func breakDuration(_ kind: BreakKind) -> TimeInterval {
        core.duration(of: kind)
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var isOnBreak: Bool {
        if case .onBreak = state { return true }
        return false
    }

    /// One line describing the current state, shown at the top of the menu.
    func statusText(now: Date = Date()) -> String {
        switch state {
        case .working(let deadline):
            let suffix = core.nextBreakKind == .long ? " (long break)" : ""
            return "Next break in \(TimeFormat.clock(deadline.timeIntervalSince(now)))\(suffix)"
        case .preBreakWarning(let breakAt):
            return "Break starts in \(TimeFormat.clock(breakAt.timeIntervalSince(now)))"
        case .holding(let reason, _):
            return "Break is waiting \(reason.waitingDescription)"
        case .onBreak(_, _, let endsAt):
            return "On a break – \(TimeFormat.clock(endsAt.timeIntervalSince(now))) left"
        case .paused(let until, let source):
            if source == .focus {
                return "Paused by Focus"
            }
            if let until = until {
                return "Paused until \(TimeFormat.dayAndTime(until))"
            }
            return "Paused"
        case .idle:
            return "You're away – the timer restarts when you're back"
        case .outsideOfficeHours(let resumesAt):
            if let resumesAt = resumesAt {
                return "Outside office hours – back \(TimeFormat.dayAndTime(resumesAt))"
            }
            return "Outside office hours"
        }
    }

    // MARK: Ticking

    @objc private func timerFired(_ timer: Timer) {
        tick()
    }

    private func tick() {
        reconcileAwayReasons()
        core.isAway = !awayReasons.isEmpty
        finish(core.tick(now: Date(), probes: probes))
    }

    /// Applies the outcome of a tick or command: effects first, then the published state.
    private func finish(_ produced: [SchedulerEffect]) {
        for effect in produced {
            apply(effect)
        }
        if state != core.state {
            state = core.state
            saveSnapshot()
        }
        didUpdate.send()
        scheduleNextTick()
    }

    private func apply(_ effect: SchedulerEffect) {
        switch effect {
        case .breakStarted(let kind):
            currentMessage = pickMessage(for: kind)
        case .breakEnded(_, let completed, let duration):
            if completed {
                stats.record(.taken(seconds: duration))
                if settings.soundEnabled {
                    SoundPlayer.play(name: settings.soundName, volume: settings.soundVolume)
                }
            } else {
                stats.record(.skipped)
            }
        case .breakSkipped:
            stats.record(.skipped)
        case .snoozed:
            stats.record(.snoozed)
        case .naturalBreak(let duration):
            stats.record(.natural(seconds: duration))
        case .nudge:
            break
        }
        effects.send(effect)
    }

    /// Arms one timer for the next moment anything can change. While nothing is counting
    /// down on screen this is seconds apart, so an idle Blink costs next to nothing.
    private func scheduleNextTick() {
        timer?.invalidate()

        let now = Date()
        var interval: TimeInterval
        var countdownTarget: Date?

        switch core.state {
        case .working(let deadline):
            switch settings.menuBarStyle {
            case .countdown:
                interval = 1
                countdownTarget = deadline
            case .minutes:
                if deadline.timeIntervalSince(now) <= 61 {
                    interval = 1
                    countdownTarget = deadline
                } else {
                    interval = 5
                }
            case .iconOnly:
                interval = 5
            }
        case .preBreakWarning(let breakAt):
            interval = 1
            countdownTarget = breakAt
        case .onBreak(_, _, let endsAt):
            interval = 1
            countdownTarget = endsAt
        case .holding:
            interval = 1
        case .idle:
            interval = 5
        case .paused, .outsideOfficeHours:
            interval = 30
        }

        // Land just after a whole second ticks over, so the countdown never skips or stutters.
        if let target = countdownTarget {
            let remaining = target.timeIntervalSince(now)
            if remaining > 0 {
                let fraction = remaining - remaining.rounded(.down)
                interval = max(0.02, fraction + 0.01)
            }
        }
        if let wake = core.nextWakeDate(now: now) {
            interval = min(interval, max(0.02, wake.timeIntervalSince(now) + 0.01))
        }

        let next = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(timerFired(_:)),
            userInfo: nil,
            repeats: false
        )
        next.tolerance = interval >= 5 ? 1 : 0.02
        // `.common` keeps the countdown moving while a menu is open.
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func settingsDidChange() {
        finish(core.update(config: settings.scheduleConfig, now: Date()))
    }

    // MARK: Messages

    private func pickMessage(for kind: BreakKind) -> String {
        let options = settings.messages(for: kind)
        let previous = lastMessages[kind]
        let candidates = options.count > 1 ? options.filter { $0 != previous } : options
        let choice = candidates.randomElement() ?? options.first ?? ""
        lastMessages[kind] = choice
        return choice
    }

    // MARK: Pause helpers

    private func startOfNextDay(after now: Date) -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now.addingTimeInterval(24 * 3600)
        let hours = settings.officeHours
        if hours.enabled, let nextStart = hours.nextStart(after: tomorrow.addingTimeInterval(-1)) {
            return nextStart
        }
        return tomorrow
    }

    // MARK: Persistence

    private func saveSnapshot() {
        let snapshot = core.snapshot(now: Date())
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: BreakScheduler.snapshotKey)
        }
    }

    private func restoreSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: BreakScheduler.snapshotKey),
              let snapshot = try? JSONDecoder().decode(SchedulerSnapshot.self, from: data) else { return }
        core.restore(snapshot, now: Date())
        if case .onBreak(let kind, _, _) = core.state {
            currentMessage = pickMessage(for: kind)
        }
        state = core.state
    }

    // MARK: System events

    private func makeProbes() -> SchedulerProbes {
        let settings = self.settings
        return SchedulerProbes(
            secondsSinceInput: { SystemActivityMonitor.secondsSinceLastInput() },
            secondsSinceKeyPress: { SystemActivityMonitor.secondsSinceLastKeyPress() },
            smartPauseReason: { SmartPause.currentReason(settings: settings) },
            displayKeptAwake: { SystemActivityMonitor.displaySleepPrevented() }
        )
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displaysDidSleep(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displaysDidWake(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidResign(_:)), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidBecomeActive(_:)), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenDidLock(_:)), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenDidUnlock(_:)), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenSaverDidStart(_:)), name: Notification.Name("com.apple.screensaver.didstart"), object: nil)
        distributed.addObserver(self, selector: #selector(screenSaverDidStop(_:)), name: Notification.Name("com.apple.screensaver.didstop"), object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(clockDidChange(_:)), name: .NSSystemClockDidChange, object: nil)
    }

    private func setAway(_ reason: AwayReason, _ isAway: Bool) {
        if isAway {
            awayReasons.insert(reason)
        } else {
            awayReasons.remove(reason)
        }
        tick()
    }

    /// Notifications can be missed (for example if the app was not running when the screen
    /// locked). If the user is plainly back at an unlocked, awake Mac, drop any stale flags.
    private func reconcileAwayReasons() {
        guard !awayReasons.isEmpty else { return }
        guard SystemActivityMonitor.secondsSinceLastInput() < 5 else { return }
        if SystemActivityMonitor.isScreenLocked() { return }
        if !SystemActivityMonitor.isSessionOnConsole() { return }
        if SystemActivityMonitor.isMainDisplayAsleep() { return }
        awayReasons.removeAll()
    }

    @objc private func systemWillSleep(_ notification: Notification) { setAway(.systemSleep, true) }
    @objc private func systemDidWake(_ notification: Notification) { setAway(.systemSleep, false) }
    @objc private func displaysDidSleep(_ notification: Notification) { setAway(.displaySleep, true) }
    @objc private func displaysDidWake(_ notification: Notification) { setAway(.displaySleep, false) }
    @objc private func sessionDidResign(_ notification: Notification) { setAway(.sessionInactive, true) }
    @objc private func sessionDidBecomeActive(_ notification: Notification) { setAway(.sessionInactive, false) }
    @objc private func screenDidLock(_ notification: Notification) { setAway(.screenLocked, true) }
    @objc private func screenSaverDidStart(_ notification: Notification) { setAway(.screenSaver, true) }
    @objc private func screenSaverDidStop(_ notification: Notification) { setAway(.screenSaver, false) }

    @objc private func screenDidUnlock(_ notification: Notification) {
        awayReasons.remove(.screenSaver)
        setAway(.screenLocked, false)
    }

    @objc private func clockDidChange(_ notification: Notification) {
        tick()
    }
}
