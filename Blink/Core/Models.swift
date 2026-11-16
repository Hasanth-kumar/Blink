import Foundation

/// The two kinds of break Blink schedules.
enum BreakKind: String, Codable, Equatable {
    case short
    case long
}

/// Why a break that is due has not started yet.
enum HoldReason: String, Codable, Equatable {
    case typing
    case call
    case fullscreenVideo
    case screenRecording
    case presentation
    case game
    case excludedApp

    /// Reasons that prove someone is at the Mac even when keyboard and mouse are untouched.
    /// While one of these is active, a quiet keyboard is not treated as "away".
    var impliesPresence: Bool {
        switch self {
        case .call, .fullscreenVideo, .screenRecording, .presentation, .game:
            return true
        case .typing, .excludedApp:
            return false
        }
    }

    /// Completes the sentence "Break is waiting …".
    var waitingDescription: String {
        switch self {
        case .typing: return "until you pause typing"
        case .call: return "until your call ends"
        case .fullscreenVideo: return "until the video stops"
        case .screenRecording: return "until the recording ends"
        case .presentation: return "until the presentation ends"
        case .game: return "until you leave the game"
        case .excludedApp: return "until you switch apps"
        }
    }
}

/// Who asked for the pause.
enum PauseSource: String, Codable, Equatable {
    case manual
    case focus
}

enum NudgeKind: String, Codable, Equatable {
    case blink
    case posture
}

/// How the blink reminder moves.
enum BlinkNudgeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Eyes screwed shut, two quick releases, then a contented smile.
    case squeeze
    /// Open eyes blinking at a natural speed.
    case natural
    /// Two slow, complete blinks to follow along with.
    case slow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .squeeze: return "Squeeze (classic)"
        case .natural: return "Natural blink"
        case .slow: return "Slow, full blink"
        }
    }

    /// The optional line of text shown under the animation.
    var caption: String {
        switch self {
        case .squeeze, .natural: return "Remember to blink"
        case .slow: return "Blink slowly and fully"
        }
    }
}

/// How the posture reminder moves.
enum PostureNudgeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A chevron that stretches the reminder upward and becomes an arrow.
    case rise
    /// A slouched figure that sits up tall.
    case sitTall
    /// Shoulders that lift, hold and drop.
    case shoulders
    /// A head that tips gently from side to side.
    case neck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rise: return "Rise (classic)"
        case .sitTall: return "Slouch to upright"
        case .shoulders: return "Shoulder release"
        case .neck: return "Neck stretch"
        }
    }

    /// The optional line of text shown under the animation.
    var caption: String {
        switch self {
        case .rise, .sitTall: return "Sit tall and relax your shoulders"
        case .shoulders: return "Lift your shoulders, then let them drop"
        case .neck: return "Ease your neck from side to side"
        }
    }
}

/// How large a reminder is drawn.
enum NudgeSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Diameter of the reminder, in points.
    var diameter: Double {
        switch self {
        case .small: return 64
        case .medium: return 88
        case .large: return 116
        }
    }
}

/// Where on the display a reminder appears.
enum NudgePosition: String, CaseIterable, Identifiable, Sendable {
    case center
    case top
    case bottom
    case topRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center: return "Centre of the screen"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .topRight: return "Top right"
        }
    }
}

/// The scheduler's single source of truth. Every deadline is a wall-clock `Date`,
/// so the state stays correct across sleep, wake and missed timer ticks.
enum SchedulerState: Equatable, Codable {
    /// Counting down to the next break.
    case working(deadline: Date)
    /// The heads-up is on screen; the break starts at `breakAt`.
    case preBreakWarning(breakAt: Date)
    /// A break is due but something (typing, a call, a video…) is in the way.
    case holding(reason: HoldReason, since: Date)
    /// The break screen is showing.
    case onBreak(kind: BreakKind, startedAt: Date, endsAt: Date)
    /// Paused by the user (optionally until a date) or by a Focus Filter.
    case paused(until: Date?, source: PauseSource)
    /// Nobody is at the Mac: idle, locked, asleep or showing the screen saver.
    case idle(since: Date)
    /// Office hours are on and this moment is outside them.
    case outsideOfficeHours(resumesAt: Date?)
}

/// Things that happened during a tick or a command. The engine reports them;
/// the app layer turns them into sounds, statistics and nudges.
enum SchedulerEffect: Equatable {
    case breakStarted(kind: BreakKind)
    case breakEnded(kind: BreakKind, completed: Bool, duration: TimeInterval)
    /// A break was skipped before it reached the screen.
    case breakSkipped
    case snoozed(TimeInterval)
    /// The user was away long enough to count as a break on their own.
    case naturalBreak(duration: TimeInterval)
    case nudge(NudgeKind)
}

/// Everything the engine needs to know about the user's preferences, as plain values.
struct ScheduleConfig: Equatable {
    var workInterval: TimeInterval
    var shortBreak: TimeInterval
    var longBreakEnabled: Bool
    /// Every Nth break is a long one.
    var longBreakEvery: Int
    var longBreak: TimeInterval
    var warningEnabled: Bool
    var warningLead: TimeInterval
    /// `nil` means snoozing is unlimited.
    var snoozeLimit: Int?
    var idleResetEnabled: Bool
    var idleThreshold: TimeInterval
    var deferWhileTyping: Bool
    /// Seconds without a key press before a held break may start.
    var typingQuiet: TimeInterval
    /// Longest a break will wait for a pause in typing.
    var maxTypingHold: TimeInterval
    /// Length of the short heads-up shown after a call / video / recording ends.
    var holdGrace: TimeInterval
    var officeHours: OfficeHours
    /// `nil` turns the nudge off.
    var blinkInterval: TimeInterval?
    var postureInterval: TimeInterval?
    var strictMode: Bool
}

/// Live readings from the system. They are closures so the engine only pays for a
/// reading (window list, camera, microphone…) at the moments it actually needs one.
struct SchedulerProbes {
    var secondsSinceInput: () -> TimeInterval
    var secondsSinceKeyPress: () -> TimeInterval
    /// A call, video, recording, presentation, game or excluded app that should hold a break.
    var smartPauseReason: () -> HoldReason?
    /// True while some app keeps the display awake (video playback, video calls).
    var displayKeptAwake: () -> Bool
}

/// What is written to disk so a relaunch can pick up where the app left off.
struct SchedulerSnapshot: Codable {
    var state: SchedulerState
    var snoozesUsed: Int
    var breaksSinceLong: Int
    var savedAt: Date
}
