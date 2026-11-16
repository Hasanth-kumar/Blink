import Foundation
import Combine

// MARK: - Setting value types

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconOnly
    case minutes
    case countdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly: return "Icon only"
        case .minutes: return "Icon and minutes left"
        case .countdown: return "Icon and live countdown"
        }
    }
}

enum BreakBackground: String, CaseIterable, Identifiable {
    case blur
    case solid
    case gradient
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blur: return "Blurred desktop"
        case .solid: return "Solid colour"
        case .gradient: return "Gradient"
        case .image: return "Custom image"
        }
    }
}

/// An app that should never be interrupted while it is frontmost.
struct ExcludedApp: Codable, Identifiable, Equatable {
    var bundleID: String
    var name: String
    var path: String

    var id: String { bundleID }
}

/// A recorded global keyboard shortcut.
struct HotKey: Codable, Equatable {
    /// Virtual key code, as reported by `NSEvent.keyCode`.
    var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `optionKey`, …).
    var modifiers: UInt32
    /// Human-readable form, for example "⌃⌥B".
    var display: String
}

enum HotKeyAction: String, CaseIterable, Identifiable {
    case startBreak
    case skipBreak
    case togglePause

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startBreak: return "Start a break now"
        case .skipBreak: return "Skip the break"
        case .togglePause: return "Pause or resume"
        }
    }

    /// Identifier handed to the system when the shortcut is registered.
    var carbonID: UInt32 {
        switch self {
        case .startBreak: return 1
        case .skipBreak: return 2
        case .togglePause: return 3
        }
    }
}

// MARK: - Settings store

/// Every user preference, backed by `UserDefaults`.
///
/// One observable object is shared by the Settings window and the scheduler, so a
/// change made in the UI reaches the engine without any extra plumbing.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultShortMessages = [
        "Look at something far away",
        "Rest your eyes on the horizon",
        "Blink slowly, a few times",
        "Let your shoulders drop",
        "Soften your gaze and breathe",
        "Find the farthest thing you can see"
    ]

    static let defaultLongMessages = [
        "Stand up and stretch",
        "Take a short walk",
        "Pour yourself a glass of water",
        "Step away from the screen for a bit",
        "Roll your shoulders and loosen your neck"
    ]

    private let defaults: UserDefaults

    // MARK: General

    @Published var showInDock: Bool { didSet { defaults.set(showInDock, forKey: Key.showInDock) } }
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) } }
    @Published var hasLaunchedBefore: Bool { didSet { defaults.set(hasLaunchedBefore, forKey: Key.hasLaunchedBefore) } }

    // MARK: Break schedule

    @Published var workMinutes: Int { didSet { defaults.set(workMinutes, forKey: Key.workMinutes) } }
    @Published var shortBreakSeconds: Int { didSet { defaults.set(shortBreakSeconds, forKey: Key.shortBreakSeconds) } }
    @Published var longBreakEnabled: Bool { didSet { defaults.set(longBreakEnabled, forKey: Key.longBreakEnabled) } }
    @Published var longBreakEvery: Int { didSet { defaults.set(longBreakEvery, forKey: Key.longBreakEvery) } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: Key.longBreakMinutes) } }

    // MARK: Heads-up

    @Published var warningEnabled: Bool { didSet { defaults.set(warningEnabled, forKey: Key.warningEnabled) } }
    @Published var warningLeadSeconds: Int { didSet { defaults.set(warningLeadSeconds, forKey: Key.warningLeadSeconds) } }
    @Published var warningCompact: Bool { didSet { defaults.set(warningCompact, forKey: Key.warningCompact) } }
    @Published var snoozeLimitEnabled: Bool { didSet { defaults.set(snoozeLimitEnabled, forKey: Key.snoozeLimitEnabled) } }
    @Published var snoozeLimit: Int { didSet { defaults.set(snoozeLimit, forKey: Key.snoozeLimit) } }
    @Published var showSnoozesLeft: Bool { didSet { defaults.set(showSnoozesLeft, forKey: Key.showSnoozesLeft) } }

    // MARK: Office hours

    @Published var officeHoursEnabled: Bool { didSet { defaults.set(officeHoursEnabled, forKey: Key.officeHoursEnabled) } }
    /// `Calendar` weekday numbers, 1 = Sunday.
    @Published var officeDays: [Int] { didSet { defaults.set(officeDays, forKey: Key.officeDays) } }
    @Published var officeStartMinute: Int { didSet { defaults.set(officeStartMinute, forKey: Key.officeStartMinute) } }
    @Published var officeEndMinute: Int { didSet { defaults.set(officeEndMinute, forKey: Key.officeEndMinute) } }

    // MARK: Smart pause

    @Published var idleResetEnabled: Bool { didSet { defaults.set(idleResetEnabled, forKey: Key.idleResetEnabled) } }
    @Published var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: Key.idleMinutes) } }
    @Published var pauseDuringCalls: Bool { didSet { defaults.set(pauseDuringCalls, forKey: Key.pauseDuringCalls) } }
    @Published var pauseDuringFullscreenVideo: Bool { didSet { defaults.set(pauseDuringFullscreenVideo, forKey: Key.pauseDuringFullscreenVideo) } }
    @Published var pauseDuringScreenRecording: Bool { didSet { defaults.set(pauseDuringScreenRecording, forKey: Key.pauseDuringScreenRecording) } }
    @Published var pauseDuringPresentations: Bool { didSet { defaults.set(pauseDuringPresentations, forKey: Key.pauseDuringPresentations) } }
    @Published var pauseDuringGames: Bool { didSet { defaults.set(pauseDuringGames, forKey: Key.pauseDuringGames) } }
    @Published var deferWhileTyping: Bool { didSet { defaults.set(deferWhileTyping, forKey: Key.deferWhileTyping) } }
    @Published var typingQuietSeconds: Int { didSet { defaults.set(typingQuietSeconds, forKey: Key.typingQuietSeconds) } }
    @Published var excludedApps: [ExcludedApp] { didSet { AppSettings.store(excludedApps, in: defaults, key: Key.excludedApps) } }

    // MARK: Break screen

    @Published var backgroundStyle: BreakBackground { didSet { defaults.set(backgroundStyle.rawValue, forKey: Key.backgroundStyle) } }
    @Published var solidColorHex: String { didSet { defaults.set(solidColorHex, forKey: Key.solidColorHex) } }
    @Published var gradientPreset: String { didSet { defaults.set(gradientPreset, forKey: Key.gradientPreset) } }
    @Published var customImagePath: String { didSet { defaults.set(customImagePath, forKey: Key.customImagePath) } }
    @Published var shortMessages: [String] { didSet { defaults.set(shortMessages, forKey: Key.shortMessages) } }
    @Published var longMessages: [String] { didSet { defaults.set(longMessages, forKey: Key.longMessages) } }
    @Published var strictMode: Bool { didSet { defaults.set(strictMode, forKey: Key.strictMode) } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }
    @Published var soundName: String { didSet { defaults.set(soundName, forKey: Key.soundName) } }
    @Published var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: Key.soundVolume) } }

    // MARK: Wellness

    @Published var blinkEnabled: Bool { didSet { defaults.set(blinkEnabled, forKey: Key.blinkEnabled) } }
    @Published var blinkMinutes: Int { didSet { defaults.set(blinkMinutes, forKey: Key.blinkMinutes) } }
    @Published var postureEnabled: Bool { didSet { defaults.set(postureEnabled, forKey: Key.postureEnabled) } }
    @Published var postureMinutes: Int { didSet { defaults.set(postureMinutes, forKey: Key.postureMinutes) } }
    /// How each reminder moves and sounds, and how reminders look on screen.
    @Published var blinkStyle: BlinkNudgeStyle { didSet { defaults.set(blinkStyle.rawValue, forKey: Key.blinkStyle) } }
    @Published var blinkSoundEnabled: Bool { didSet { defaults.set(blinkSoundEnabled, forKey: Key.blinkSoundEnabled) } }
    @Published var postureStyle: PostureNudgeStyle { didSet { defaults.set(postureStyle.rawValue, forKey: Key.postureStyle) } }
    @Published var postureSoundEnabled: Bool { didSet { defaults.set(postureSoundEnabled, forKey: Key.postureSoundEnabled) } }
    @Published var nudgeVolume: Double { didSet { defaults.set(nudgeVolume, forKey: Key.nudgeVolume) } }
    @Published var nudgeSize: NudgeSize { didSet { defaults.set(nudgeSize.rawValue, forKey: Key.nudgeSize) } }
    @Published var nudgePosition: NudgePosition { didSet { defaults.set(nudgePosition.rawValue, forKey: Key.nudgePosition) } }
    @Published var nudgeDimsScreen: Bool { didSet { defaults.set(nudgeDimsScreen, forKey: Key.nudgeDimsScreen) } }
    @Published var nudgeShowsCaption: Bool { didSet { defaults.set(nudgeShowsCaption, forKey: Key.nudgeShowsCaption) } }

    // MARK: Shortcuts

    @Published var hotKeyStartBreak: HotKey? { didSet { AppSettings.storeOptional(hotKeyStartBreak, in: defaults, key: Key.hotKeyStartBreak) } }
    @Published var hotKeySkipBreak: HotKey? { didSet { AppSettings.storeOptional(hotKeySkipBreak, in: defaults, key: Key.hotKeySkipBreak) } }
    @Published var hotKeyTogglePause: HotKey? { didSet { AppSettings.storeOptional(hotKeyTogglePause, in: defaults, key: Key.hotKeyTogglePause) } }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        showInDock = AppSettings.bool(defaults, Key.showInDock, false)
        menuBarStyle = MenuBarStyle(rawValue: AppSettings.string(defaults, Key.menuBarStyle, "")) ?? .minutes
        hasLaunchedBefore = AppSettings.bool(defaults, Key.hasLaunchedBefore, false)

        workMinutes = AppSettings.int(defaults, Key.workMinutes, 20, 1...240)
        shortBreakSeconds = AppSettings.int(defaults, Key.shortBreakSeconds, 20, 5...600)
        longBreakEnabled = AppSettings.bool(defaults, Key.longBreakEnabled, false)
        longBreakEvery = AppSettings.int(defaults, Key.longBreakEvery, 4, 2...12)
        longBreakMinutes = AppSettings.int(defaults, Key.longBreakMinutes, 5, 1...60)

        warningEnabled = AppSettings.bool(defaults, Key.warningEnabled, true)
        warningLeadSeconds = AppSettings.int(defaults, Key.warningLeadSeconds, 60, 5...300)
        warningCompact = AppSettings.bool(defaults, Key.warningCompact, false)
        snoozeLimitEnabled = AppSettings.bool(defaults, Key.snoozeLimitEnabled, true)
        snoozeLimit = AppSettings.int(defaults, Key.snoozeLimit, 3, 1...10)
        showSnoozesLeft = AppSettings.bool(defaults, Key.showSnoozesLeft, true)

        officeHoursEnabled = AppSettings.bool(defaults, Key.officeHoursEnabled, false)
        officeDays = (defaults.array(forKey: Key.officeDays) as? [Int]) ?? [2, 3, 4, 5, 6]
        officeStartMinute = AppSettings.int(defaults, Key.officeStartMinute, 9 * 60, 0...1439)
        officeEndMinute = AppSettings.int(defaults, Key.officeEndMinute, 18 * 60, 0...1439)

        idleResetEnabled = AppSettings.bool(defaults, Key.idleResetEnabled, true)
        idleMinutes = AppSettings.int(defaults, Key.idleMinutes, 5, 1...60)
        pauseDuringCalls = AppSettings.bool(defaults, Key.pauseDuringCalls, true)
        pauseDuringFullscreenVideo = AppSettings.bool(defaults, Key.pauseDuringFullscreenVideo, true)
        pauseDuringScreenRecording = AppSettings.bool(defaults, Key.pauseDuringScreenRecording, true)
        pauseDuringPresentations = AppSettings.bool(defaults, Key.pauseDuringPresentations, true)
        pauseDuringGames = AppSettings.bool(defaults, Key.pauseDuringGames, true)
        deferWhileTyping = AppSettings.bool(defaults, Key.deferWhileTyping, true)
        typingQuietSeconds = AppSettings.int(defaults, Key.typingQuietSeconds, 3, 1...15)
        excludedApps = AppSettings.load([ExcludedApp].self, from: defaults, key: Key.excludedApps) ?? []

        backgroundStyle = BreakBackground(rawValue: AppSettings.string(defaults, Key.backgroundStyle, "")) ?? .blur
        solidColorHex = AppSettings.string(defaults, Key.solidColorHex, "#16213A")
        gradientPreset = AppSettings.string(defaults, Key.gradientPreset, "dusk")
        customImagePath = AppSettings.string(defaults, Key.customImagePath, "")
        shortMessages = (defaults.array(forKey: Key.shortMessages) as? [String]) ?? AppSettings.defaultShortMessages
        longMessages = (defaults.array(forKey: Key.longMessages) as? [String]) ?? AppSettings.defaultLongMessages
        strictMode = AppSettings.bool(defaults, Key.strictMode, false)
        soundEnabled = AppSettings.bool(defaults, Key.soundEnabled, true)
        soundName = AppSettings.string(defaults, Key.soundName, "Glass")
        soundVolume = AppSettings.double(defaults, Key.soundVolume, 0.6, 0...1)

        blinkEnabled = AppSettings.bool(defaults, Key.blinkEnabled, false)
        blinkMinutes = AppSettings.int(defaults, Key.blinkMinutes, 5, 1...60)
        postureEnabled = AppSettings.bool(defaults, Key.postureEnabled, false)
        postureMinutes = AppSettings.int(defaults, Key.postureMinutes, 30, 5...120)
        blinkStyle = BlinkNudgeStyle(rawValue: AppSettings.string(defaults, Key.blinkStyle, "")) ?? .squeeze
        blinkSoundEnabled = AppSettings.bool(defaults, Key.blinkSoundEnabled, true)
        postureStyle = PostureNudgeStyle(rawValue: AppSettings.string(defaults, Key.postureStyle, "")) ?? .rise
        postureSoundEnabled = AppSettings.bool(defaults, Key.postureSoundEnabled, true)
        nudgeVolume = AppSettings.double(defaults, Key.nudgeVolume, 0.5, 0...1)
        nudgeSize = NudgeSize(rawValue: AppSettings.string(defaults, Key.nudgeSize, "")) ?? .medium
        nudgePosition = NudgePosition(rawValue: AppSettings.string(defaults, Key.nudgePosition, "")) ?? .center
        nudgeDimsScreen = AppSettings.bool(defaults, Key.nudgeDimsScreen, true)
        nudgeShowsCaption = AppSettings.bool(defaults, Key.nudgeShowsCaption, false)

        hotKeyStartBreak = AppSettings.load(HotKey.self, from: defaults, key: Key.hotKeyStartBreak)
        hotKeySkipBreak = AppSettings.load(HotKey.self, from: defaults, key: Key.hotKeySkipBreak)
        hotKeyTogglePause = AppSettings.load(HotKey.self, from: defaults, key: Key.hotKeyTogglePause)
    }

    // MARK: Derived values

    var officeHours: OfficeHours {
        OfficeHours(
            enabled: officeHoursEnabled,
            weekdays: Set(officeDays),
            startMinute: officeStartMinute,
            endMinute: officeEndMinute
        )
    }

    /// The preferences the scheduling engine cares about, as plain values.
    var scheduleConfig: ScheduleConfig {
        ScheduleConfig(
            workInterval: TimeInterval(workMinutes * 60),
            shortBreak: TimeInterval(shortBreakSeconds),
            longBreakEnabled: longBreakEnabled,
            longBreakEvery: longBreakEvery,
            longBreak: TimeInterval(longBreakMinutes * 60),
            warningEnabled: warningEnabled,
            warningLead: TimeInterval(warningLeadSeconds),
            snoozeLimit: snoozeLimitEnabled ? snoozeLimit : nil,
            idleResetEnabled: idleResetEnabled,
            idleThreshold: TimeInterval(idleMinutes * 60),
            deferWhileTyping: deferWhileTyping,
            typingQuiet: TimeInterval(typingQuietSeconds),
            maxTypingHold: 60,
            holdGrace: 10,
            officeHours: officeHours,
            blinkInterval: blinkEnabled ? TimeInterval(blinkMinutes * 60) : nil,
            postureInterval: postureEnabled ? TimeInterval(postureMinutes * 60) : nil,
            strictMode: strictMode
        )
    }

    func hotKey(for action: HotKeyAction) -> HotKey? {
        switch action {
        case .startBreak: return hotKeyStartBreak
        case .skipBreak: return hotKeySkipBreak
        case .togglePause: return hotKeyTogglePause
        }
    }

    func setHotKey(_ hotKey: HotKey?, for action: HotKeyAction) {
        switch action {
        case .startBreak: hotKeyStartBreak = hotKey
        case .skipBreak: hotKeySkipBreak = hotKey
        case .togglePause: hotKeyTogglePause = hotKey
        }
    }

    /// Messages for a break of the given kind, with blank lines removed and a fallback if none are left.
    func messages(for kind: BreakKind) -> [String] {
        let source = kind == .long ? longMessages : shortMessages
        let cleaned = source
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleaned.isEmpty { return cleaned }
        return kind == .long ? AppSettings.defaultLongMessages : AppSettings.defaultShortMessages
    }

    // MARK: UserDefaults helpers

    private enum Key {
        static let showInDock = "showInDock"
        static let menuBarStyle = "menuBarStyle"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let workMinutes = "workMinutes"
        static let shortBreakSeconds = "shortBreakSeconds"
        static let longBreakEnabled = "longBreakEnabled"
        static let longBreakEvery = "longBreakEvery"
        static let longBreakMinutes = "longBreakMinutes"
        static let warningEnabled = "warningEnabled"
        static let warningLeadSeconds = "warningLeadSeconds"
        static let warningCompact = "warningCompact"
        static let snoozeLimitEnabled = "snoozeLimitEnabled"
        static let snoozeLimit = "snoozeLimit"
        static let showSnoozesLeft = "showSnoozesLeft"
        static let officeHoursEnabled = "officeHoursEnabled"
        static let officeDays = "officeDays"
        static let officeStartMinute = "officeStartMinute"
        static let officeEndMinute = "officeEndMinute"
        static let idleResetEnabled = "idleResetEnabled"
        static let idleMinutes = "idleMinutes"
        static let pauseDuringCalls = "pauseDuringCalls"
        static let pauseDuringFullscreenVideo = "pauseDuringFullscreenVideo"
        static let pauseDuringScreenRecording = "pauseDuringScreenRecording"
        static let pauseDuringPresentations = "pauseDuringPresentations"
        static let pauseDuringGames = "pauseDuringGames"
        static let deferWhileTyping = "deferWhileTyping"
        static let typingQuietSeconds = "typingQuietSeconds"
        static let excludedApps = "excludedApps"
        static let backgroundStyle = "backgroundStyle"
        static let solidColorHex = "solidColorHex"
        static let gradientPreset = "gradientPreset"
        static let customImagePath = "customImagePath"
        static let shortMessages = "shortMessages"
        static let longMessages = "longMessages"
        static let strictMode = "strictMode"
        static let soundEnabled = "soundEnabled"
        static let soundName = "soundName"
        static let soundVolume = "soundVolume"
        static let blinkEnabled = "blinkEnabled"
        static let blinkMinutes = "blinkMinutes"
        static let postureEnabled = "postureEnabled"
        static let postureMinutes = "postureMinutes"
        static let blinkStyle = "blinkStyle"
        static let blinkSoundEnabled = "blinkSoundEnabled"
        static let postureStyle = "postureStyle"
        static let postureSoundEnabled = "postureSoundEnabled"
        static let nudgeVolume = "nudgeVolume"
        static let nudgeSize = "nudgeSize"
        static let nudgePosition = "nudgePosition"
        static let nudgeDimsScreen = "nudgeDimsScreen"
        static let nudgeShowsCaption = "nudgeShowsCaption"
        static let hotKeyStartBreak = "hotKeyStartBreak"
        static let hotKeySkipBreak = "hotKeySkipBreak"
        static let hotKeyTogglePause = "hotKeyTogglePause"
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func int(_ defaults: UserDefaults, _ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
        let value = defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func double(_ defaults: UserDefaults, _ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        let value = defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func string(_ defaults: UserDefaults, _ key: String, _ fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }

    private static func store<Value: Encodable>(_ value: Value, in defaults: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func storeOptional<Value: Encodable>(_ value: Value?, in defaults: UserDefaults, key: String) {
        if let value = value {
            store(value, in: defaults, key: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from defaults: UserDefaults, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
