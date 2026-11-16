import Foundation

/// The break state machine.
///
/// It owns no timers and touches no system APIs. The app layer (`BreakScheduler`)
/// calls `tick(now:probes:)` whenever time may have moved on, forwards user commands,
/// and reacts to the effects each call returns. Every deadline is a wall-clock `Date`,
/// so a late or missing tick can delay a transition but never corrupt the schedule.
final class SchedulerCore {

    // MARK: Tunables

    /// A gap between ticks longer than this means the Mac slept or the app was suspended.
    static let maxTickGap: TimeInterval = 90
    /// How recent the last input must be before an away user counts as "back".
    static let idleExitWindow: TimeInterval = 12
    /// After returning to work, nudges stay quiet for this long.
    static let nudgeSettleTime: TimeInterval = 60
    /// Minimum distance between a blink nudge and a posture nudge.
    static let nudgeSpacing: TimeInterval = 15

    // MARK: State

    private(set) var state: SchedulerState
    private(set) var config: ScheduleConfig
    private(set) var snoozesUsed = 0
    private(set) var breaksSinceLong = 0
    private(set) var focusPauseActive = false
    /// Length of the heads-up currently (or most recently) on screen.
    private(set) var warningLength: TimeInterval

    /// Set by the app layer while the screen is locked, asleep or showing the screen saver.
    var isAway = false

    private var focusPauseOverridden = false
    private var cycleLead: TimeInterval
    private var cycleLength: TimeInterval
    private var remainingBeforeIdle: TimeInterval = 0
    private var typingHoldSince: Date?
    private var holdNeedsGrace = false
    private var stateAfterBreak: SchedulerState?
    private var nextBlinkAt: Date?
    private var nextPostureAt: Date?
    private var lastTick: Date?
    private var pendingEffects: [SchedulerEffect] = []

    init(config: ScheduleConfig, now: Date) {
        let lead = SchedulerCore.lead(for: config)
        self.config = config
        self.cycleLead = lead
        self.warningLength = lead
        self.cycleLength = config.workInterval
        self.state = .working(deadline: now.addingTimeInterval(config.workInterval))
        self.nextBlinkAt = config.blinkInterval.map { now.addingTimeInterval($0) }
        self.nextPostureAt = config.postureInterval.map { now.addingTimeInterval($0) }
    }

    // MARK: Derived values

    /// The kind of break that will come next.
    var nextBreakKind: BreakKind {
        guard config.longBreakEnabled, config.longBreakEvery > 0 else { return .short }
        return breaksSinceLong + 1 >= config.longBreakEvery ? .long : .short
    }

    func duration(of kind: BreakKind) -> TimeInterval {
        kind == .long ? config.longBreak : config.shortBreak
    }

    /// `nil` when snoozing is unlimited.
    var snoozesRemaining: Int? {
        guard let limit = config.snoozeLimit else { return nil }
        return max(0, limit - snoozesUsed)
    }

    var canSnooze: Bool {
        guard let remaining = snoozesRemaining else { return true }
        return remaining > 0
    }

    var canSkip: Bool { !config.strictMode }

    /// The next moment something is scheduled to happen, so the app layer can sleep until then.
    func nextWakeDate(now: Date) -> Date? {
        switch state {
        case .working(let deadline):
            var candidates: [Date] = [deadline]
            if config.warningEnabled, cycleLead > 0 {
                let warningAt = deadline.addingTimeInterval(-cycleLead)
                if warningAt > now { candidates.append(warningAt) }
            }
            if let blink = nextBlinkAt, blink > now { candidates.append(blink) }
            if let posture = nextPostureAt, posture > now { candidates.append(posture) }
            return candidates.min()
        case .preBreakWarning(let breakAt):
            return breakAt
        case .onBreak(_, _, let endsAt):
            return endsAt
        case .paused(let until, _):
            return until
        case .outsideOfficeHours(let resumesAt):
            return resumesAt
        case .holding, .idle:
            return nil
        }
    }

    // MARK: Ticking

    /// Advances the machine to `now`. Safe to call at any frequency.
    @discardableResult
    func tick(now: Date, probes: SchedulerProbes) -> [SchedulerEffect] {
        detectTimeGap(now: now)
        lastTick = now

        // One tick may legitimately pass through two states (for example
        // "outside office hours" → "working"); settle, but never spin.
        var passes = 0
        while passes < 4 {
            let before = state
            step(now: now, probes: probes)
            if state == before { break }
            passes += 1
        }
        return drain()
    }

    private func step(now: Date, probes: SchedulerProbes) {
        switch state {
        case .paused(let until, _):
            if let until = until, now >= until {
                beginWorking(now: now)
            }

        case .outsideOfficeHours:
            if config.officeHours.contains(now) {
                beginWorking(now: now)
            }

        case .idle(let since):
            guard !isAway, probes.secondsSinceInput() < SchedulerCore.idleExitWindow else { return }
            let away = now.timeIntervalSince(since)
            if away >= config.shortBreak {
                creditNaturalBreak(duration: away, now: now)
            } else {
                // A very short absence: carry on with the time that was left.
                state = .working(deadline: now.addingTimeInterval(max(remainingBeforeIdle, 5)))
            }

        case .working(let deadline):
            if !config.officeHours.contains(now) {
                state = .outsideOfficeHours(resumesAt: config.officeHours.nextStart(after: now))
                return
            }
            if enterIdleIfNeeded(now: now, probes: probes, remaining: deadline.timeIntervalSince(now), checkInput: true) {
                return
            }
            // The clock was moved backwards far enough to stretch the wait past a full cycle.
            if deadline.timeIntervalSince(now) > max(cycleLength, config.workInterval) + 5 {
                state = .working(deadline: now.addingTimeInterval(cycleLength))
                return
            }
            emitNudgesIfDue(now: now, deadline: deadline)
            if now >= deadline {
                breakDue(now: now, probes: probes)
                return
            }
            if config.warningEnabled, cycleLead > 0, now >= deadline.addingTimeInterval(-cycleLead) {
                // Don't flash a heads-up over a call or a video; the break will be held instead.
                if probes.smartPauseReason() == nil {
                    warningLength = cycleLead
                    state = .preBreakWarning(breakAt: deadline)
                }
            }

        case .preBreakWarning(let breakAt):
            if isAway {
                enterIdle(since: now, remaining: breakAt.timeIntervalSince(now))
                return
            }
            if now >= breakAt {
                breakDue(now: now, probes: probes)
            }

        case .holding(let reason, let since):
            if enterIdleIfNeeded(now: now, probes: probes, remaining: 0, checkInput: !reason.impliesPresence) {
                return
            }
            if let current = currentHoldReason(probes: probes) {
                if current == .typing {
                    let started = typingHoldSince ?? now
                    typingHoldSince = started
                    if now.timeIntervalSince(started) >= config.maxTypingHold {
                        // They have been typing non-stop; don't wait forever.
                        startBreak(kind: nextBreakKind, now: now)
                        return
                    }
                } else {
                    typingHoldSince = nil
                    holdNeedsGrace = true
                }
                if current != reason {
                    state = .holding(reason: current, since: since)
                }
                return
            }
            // Nothing is in the way any more.
            if holdNeedsGrace, config.warningEnabled, config.holdGrace > 0 {
                holdNeedsGrace = false
                typingHoldSince = nil
                warningLength = config.holdGrace
                state = .preBreakWarning(breakAt: now.addingTimeInterval(config.holdGrace))
            } else {
                startBreak(kind: nextBreakKind, now: now)
            }

        case .onBreak(let kind, let startedAt, let endsAt):
            if now >= endsAt {
                finishBreak(kind: kind, startedAt: startedAt, endsAt: endsAt, completed: true, now: now)
            }
        }
    }

    /// If far more time passed than any tick interval allows, the Mac was asleep
    /// (or the app was suspended) and the user had a break whether we saw it or not.
    private func detectTimeGap(now: Date) {
        guard let last = lastTick else { return }
        let gap = now.timeIntervalSince(last)
        guard gap > SchedulerCore.maxTickGap else { return }
        switch state {
        case .working, .preBreakWarning, .holding:
            creditNaturalBreak(duration: gap, now: now)
        case .onBreak, .paused, .idle, .outsideOfficeHours:
            break
        }
    }

    // MARK: Commands

    /// Starts a break immediately, ignoring smart pause.
    @discardableResult
    func startBreakNow(now: Date) -> [SchedulerEffect] {
        switch state {
        case .onBreak:
            return drain()
        case .paused(_, .manual):
            // Taking a break by hand should not cancel a pause the user set.
            stateAfterBreak = state
        default:
            stateAfterBreak = nil
        }
        startBreak(kind: nextBreakKind, now: now)
        return drain()
    }

    /// Skips the break that is showing, or the next one if none is. Ignored in strict mode.
    @discardableResult
    func skip(now: Date) -> [SchedulerEffect] {
        guard canSkip else { return drain() }
        switch state {
        case .onBreak(let kind, let startedAt, let endsAt):
            finishBreak(kind: kind, startedAt: startedAt, endsAt: endsAt, completed: false, now: now)
        case .working, .preBreakWarning, .holding:
            pendingEffects.append(.breakSkipped)
            advanceCycle(after: nextBreakKind)
            snoozesUsed = 0
            beginWorking(now: now)
        case .paused, .idle, .outsideOfficeHours:
            break
        }
        return drain()
    }

    /// Pushes the upcoming break back by `duration`, if the snooze limit allows it.
    @discardableResult
    func snooze(_ duration: TimeInterval, now: Date) -> [SchedulerEffect] {
        switch state {
        case .working, .preBreakWarning, .holding:
            guard canSnooze, duration > 0 else { return drain() }
            snoozesUsed += 1
            cycleLength = duration
            cycleLead = min(config.warningLead, 15, duration / 2)
            typingHoldSince = nil
            holdNeedsGrace = false
            state = .working(deadline: now.addingTimeInterval(duration))
            pendingEffects.append(.snoozed(duration))
        case .onBreak, .paused, .idle, .outsideOfficeHours:
            break
        }
        return drain()
    }

    /// Pauses until `until`, or indefinitely when it is `nil`.
    @discardableResult
    func pause(until: Date?, now: Date) -> [SchedulerEffect] {
        if case .onBreak = state { return drain() }
        typingHoldSince = nil
        holdNeedsGrace = false
        stateAfterBreak = nil
        state = .paused(until: until, source: .manual)
        return drain()
    }

    @discardableResult
    func resume(now: Date) -> [SchedulerEffect] {
        if case .paused(_, let source) = state {
            if source == .focus {
                // The user overrode the Focus Filter; respect that until the Focus changes.
                focusPauseOverridden = true
            }
            beginWorking(now: now)
        }
        return drain()
    }

    /// Called when a Focus Filter turns "pause breaks" on or off.
    @discardableResult
    func setFocusPause(_ active: Bool, now: Date) -> [SchedulerEffect] {
        focusPauseActive = active
        focusPauseOverridden = false
        if active {
            switch state {
            case .working, .preBreakWarning, .holding, .idle, .outsideOfficeHours:
                typingHoldSince = nil
                holdNeedsGrace = false
                state = .paused(until: nil, source: .focus)
            case .onBreak, .paused:
                break
            }
        } else if case .paused(_, .focus) = state {
            beginWorking(now: now)
        }
        return drain()
    }

    /// Applies new settings.
    @discardableResult
    func update(config newConfig: ScheduleConfig, now: Date) -> [SchedulerEffect] {
        let old = config
        config = newConfig

        if old.blinkInterval != newConfig.blinkInterval {
            nextBlinkAt = newConfig.blinkInterval.map { now.addingTimeInterval($0) }
        }
        if old.postureInterval != newConfig.postureInterval {
            nextPostureAt = newConfig.postureInterval.map { now.addingTimeInterval($0) }
        }

        let intervalChanged = old.workInterval != newConfig.workInterval
        switch state {
        case .working:
            if intervalChanged {
                // Changing the interval restarts the countdown: simple and predictable.
                restartCycle(now: now)
            } else if cycleLength == newConfig.workInterval {
                cycleLead = SchedulerCore.lead(for: newConfig)
            }
        case .preBreakWarning(let breakAt):
            if intervalChanged {
                restartCycle(now: now)
            } else if !newConfig.warningEnabled {
                // The heads-up was switched off while it was showing.
                state = .working(deadline: breakAt)
            }
        case .holding, .onBreak, .paused, .idle, .outsideOfficeHours:
            break
        }
        return drain()
    }

    // MARK: Persistence

    func snapshot(now: Date) -> SchedulerSnapshot {
        SchedulerSnapshot(state: state, snoozesUsed: snoozesUsed, breaksSinceLong: breaksSinceLong, savedAt: now)
    }

    /// Picks up from a snapshot written before the app quit.
    func restore(_ snapshot: SchedulerSnapshot, now: Date) {
        let elapsed = now.timeIntervalSince(snapshot.savedAt)
        if elapsed >= 0, elapsed < 4 * 3600 {
            snoozesUsed = max(0, snapshot.snoozesUsed)
            breaksSinceLong = max(0, snapshot.breaksSinceLong)
        }

        switch snapshot.state {
        case .onBreak(_, _, let endsAt):
            // Relaunched in the middle of a break: finish it.
            if endsAt > now { state = snapshot.state }
        case .paused(let until, let source):
            if source == .manual {
                if let until = until {
                    if until > now { state = snapshot.state }
                } else {
                    state = snapshot.state
                }
            }
        case .working(let deadline):
            let remaining = deadline.timeIntervalSince(now)
            if remaining > 5, remaining <= config.workInterval {
                state = .working(deadline: deadline)
            }
        case .preBreakWarning, .holding, .idle, .outsideOfficeHours:
            break
        }
    }

    // MARK: Transitions

    private static func lead(for config: ScheduleConfig) -> TimeInterval {
        max(0, min(config.warningLead, config.workInterval / 2))
    }

    private func beginWorking(now: Date) {
        typingHoldSince = nil
        holdNeedsGrace = false
        if focusPauseActive, !focusPauseOverridden {
            state = .paused(until: nil, source: .focus)
            return
        }
        restartCycle(now: now)
        settleNudges(now: now)
    }

    private func restartCycle(now: Date) {
        cycleLength = config.workInterval
        cycleLead = SchedulerCore.lead(for: config)
        state = .working(deadline: now.addingTimeInterval(config.workInterval))
    }

    private func breakDue(now: Date, probes: SchedulerProbes) {
        if let reason = currentHoldReason(probes: probes) {
            holdNeedsGrace = reason != .typing
            typingHoldSince = reason == .typing ? now : nil
            state = .holding(reason: reason, since: now)
        } else {
            startBreak(kind: nextBreakKind, now: now)
        }
    }

    private func currentHoldReason(probes: SchedulerProbes) -> HoldReason? {
        if let reason = probes.smartPauseReason() {
            return reason
        }
        if config.deferWhileTyping, probes.secondsSinceKeyPress() < config.typingQuiet {
            return .typing
        }
        return nil
    }

    private func startBreak(kind: BreakKind, now: Date) {
        typingHoldSince = nil
        holdNeedsGrace = false
        state = .onBreak(kind: kind, startedAt: now, endsAt: now.addingTimeInterval(duration(of: kind)))
        pendingEffects.append(.breakStarted(kind: kind))
    }

    private func finishBreak(kind: BreakKind, startedAt: Date, endsAt: Date, completed: Bool, now: Date) {
        let planned = endsAt.timeIntervalSince(startedAt)
        let rested = min(max(0, now.timeIntervalSince(startedAt)), planned)
        pendingEffects.append(.breakEnded(kind: kind, completed: completed, duration: rested))
        advanceCycle(after: kind)
        snoozesUsed = 0

        if let restore = stateAfterBreak {
            stateAfterBreak = nil
            if case .paused(let until, _) = restore {
                let stillPaused: Bool
                if let until = until {
                    stillPaused = until > now
                } else {
                    stillPaused = true
                }
                if stillPaused {
                    state = restore
                    return
                }
            }
        }
        beginWorking(now: now)
    }

    private func advanceCycle(after kind: BreakKind) {
        if kind == .long {
            breaksSinceLong = 0
        } else {
            breaksSinceLong = min(breaksSinceLong + 1, 10_000)
        }
    }

    private func creditNaturalBreak(duration: TimeInterval, now: Date) {
        pendingEffects.append(.naturalBreak(duration: duration))
        if config.longBreakEnabled, duration >= config.longBreak {
            breaksSinceLong = 0
        }
        snoozesUsed = 0
        beginWorking(now: now)
    }

    /// Moves to `.idle` when the user is away. Returns true if it did.
    private func enterIdleIfNeeded(now: Date, probes: SchedulerProbes, remaining: TimeInterval, checkInput: Bool) -> Bool {
        if isAway {
            enterIdle(since: now, remaining: remaining)
            return true
        }
        guard checkInput, config.idleResetEnabled else { return false }
        let quietFor = probes.secondsSinceInput()
        guard quietFor >= config.idleThreshold else { return false }
        // Watching a film or sitting in a meeting is not being away.
        if probes.displayKeptAwake() { return false }
        if let reason = probes.smartPauseReason(), reason.impliesPresence { return false }
        enterIdle(since: now.addingTimeInterval(-quietFor), remaining: remaining)
        return true
    }

    private func enterIdle(since: Date, remaining: TimeInterval) {
        remainingBeforeIdle = max(0, remaining)
        typingHoldSince = nil
        holdNeedsGrace = false
        state = .idle(since: since)
    }

    // MARK: Nudges

    /// Keeps nudges from firing the instant the user sits back down.
    private func settleNudges(now: Date) {
        let earliest = now.addingTimeInterval(SchedulerCore.nudgeSettleTime)
        if let blink = nextBlinkAt, blink < earliest { nextBlinkAt = earliest }
        if let posture = nextPostureAt, posture < earliest {
            nextPostureAt = earliest.addingTimeInterval(SchedulerCore.nudgeSpacing)
        }
    }

    private func emitNudgesIfDue(now: Date, deadline: Date) {
        // Stay quiet when a break, or its heads-up, is about to appear.
        let quietAfter = deadline.addingTimeInterval(-(cycleLead + 10))

        if let interval = config.blinkInterval {
            let due = nextBlinkAt ?? now.addingTimeInterval(interval)
            nextBlinkAt = due
            if now >= due {
                nextBlinkAt = now.addingTimeInterval(interval)
                if now < quietAfter {
                    pendingEffects.append(.nudge(.blink))
                    if let posture = nextPostureAt, posture.timeIntervalSince(now) < SchedulerCore.nudgeSpacing {
                        nextPostureAt = now.addingTimeInterval(SchedulerCore.nudgeSpacing)
                    }
                }
            }
        } else {
            nextBlinkAt = nil
        }

        if let interval = config.postureInterval {
            let due = nextPostureAt ?? now.addingTimeInterval(interval)
            nextPostureAt = due
            if now >= due {
                nextPostureAt = now.addingTimeInterval(interval)
                if now < quietAfter {
                    pendingEffects.append(.nudge(.posture))
                }
            }
        } else {
            nextPostureAt = nil
        }
    }

    // MARK: Helpers

    private func drain() -> [SchedulerEffect] {
        let effects = pendingEffects
        pendingEffects.removeAll()
        return effects
    }
}
