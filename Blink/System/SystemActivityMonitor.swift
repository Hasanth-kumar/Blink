import AppKit
import CoreAudio
import CoreMediaIO
import IOKit.pwr_mgt

/// Read-only questions about what the Mac and the user are doing right now.
///
/// Nothing here needs a privacy permission: the camera and microphone checks read an
/// "is this device running somewhere" flag and never open the device, the idle and typing
/// checks read counters the system already keeps, and the window check reads sizes only.
@MainActor
enum SystemActivityMonitor {

    // MARK: Keyboard and mouse

    /// `kCGAnyInputEventType`, which Swift does not import.
    private static let anyInputEvent = CGEventType(rawValue: ~0) ?? .null

    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEvent)
    }

    static func secondsSinceLastKeyPress() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    // MARK: Session

    private static func sessionInfo() -> [String: Any] {
        (CGSessionCopyCurrentDictionary() as? [String: Any]) ?? [:]
    }

    static func isScreenLocked() -> Bool {
        (sessionInfo()["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    /// False while another user is switched in with Fast User Switching.
    static func isSessionOnConsole() -> Bool {
        (sessionInfo()["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue ?? true
    }

    static func isMainDisplayAsleep() -> Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    // MARK: Camera

    /// True while any app is using any camera.
    static func isCameraInUse() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == 0, dataSize > 0 else {
            return false
        }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, dataSize, &dataUsed, &devices) == 0 else {
            return false
        }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            var isRunning: UInt32 = 0
            var runningUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device,
                &runningAddress,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &runningUsed,
                &isRunning
            )
            if status == 0, isRunning != 0 {
                return true
            }
        }
        return false
    }

    // MARK: Microphone

    /// True while any app is capturing from any audio input device.
    static func isMicrophoneInUse() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == 0, dataSize > 0 else {
            return false
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &devices) == 0 else {
            return false
        }

        for device in devices where hasInputStreams(device) {
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceIsRunningSomewhere),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &size, &isRunning) == 0, isRunning != 0 {
                return true
            }
        }
        return false
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreams),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeInput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == 0 && size > 0
    }

    // MARK: Display kept awake

    /// True while another process holds a "keep the display awake" power assertion,
    /// which is what video players and video-call apps do while they are playing.
    static func displaySleepPrevented() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let cfDictionary = unmanaged?.takeRetainedValue() else {
            return false
        }
        let assertionsByProcess = cfDictionary as NSDictionary
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for (key, value) in assertionsByProcess {
            guard let pid = key as? NSNumber, pid.int32Value != ownPID,
                  let assertions = value as? [[String: Any]] else { continue }
            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String else { continue }
                guard type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleepAssertion" else { continue }
                let level = (assertion["AssertLevel"] as? NSNumber)?.intValue ?? 255
                if level != 0 {
                    return true
                }
            }
        }
        return false
    }

    // MARK: Full screen

    /// True when the frontmost app has taken over a display: a native full-screen Space,
    /// a slideshow, or a game that covers the whole screen.
    static func isFullscreen(_ app: NSRunningApplication) -> Bool {
        let options = NSApp.currentSystemPresentationOptions
        if options.contains(.fullScreen) || options.contains(.hideMenuBar) {
            return true
        }
        return ownsScreenSizedWindow(pid: app.processIdentifier)
    }

    private static func ownsScreenSizedWindow(pid: pid_t) -> Bool {
        let listOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        var displayBounds: [CGRect] = []
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                displayBounds.append(CGDisplayBounds(CGDirectDisplayID(number.uint32Value)))
            }
        }

        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == pid,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { continue }
            for display in displayBounds {
                let sameOrigin = abs(display.minX - bounds.minX) < 2 && abs(display.minY - bounds.minY) < 2
                let sameSize = abs(display.width - bounds.width) < 2 && abs(display.height - bounds.height) < 2
                if sameOrigin && sameSize {
                    return true
                }
            }
        }
        return false
    }

    // MARK: App categories

    private static let presentationApps: Set<String> = [
        "com.apple.iWork.Keynote",
        "com.microsoft.Powerpoint"
    ]

    static func isPresentationApp(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return presentationApps.contains(bundleID)
    }

    private static var gameCache: [String: Bool] = [:]

    /// True when the app declares itself a game in its Info.plist.
    static func isGame(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        if let cached = gameCache[bundleID] {
            return cached
        }
        var isGame = false
        if let url = app.bundleURL,
           let category = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String {
            isGame = category.contains("games")
        }
        gameCache[bundleID] = isGame
        return isGame
    }

    // MARK: Screen recording

    /// Apps that only run while a recording is being set up or made. macOS has no public
    /// "is the screen being recorded" switch, so this is a best-effort check; other
    /// recorders can be added to the "don't interrupt" app list instead.
    private static let recorderApps: Set<String> = [
        "com.apple.screencaptureui",
        "com.obsproject.obs-studio"
    ]

    static func isScreenRecording() -> Bool {
        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier, recorderApps.contains(bundleID) {
                return true
            }
        }
        return false
    }
}

/// Decides whether something on screen should hold a break back.
@MainActor
enum SmartPause {
    static func currentReason(settings: AppSettings) -> HoldReason? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostID = frontmost?.bundleIdentifier

        if let frontmostID = frontmostID,
           settings.excludedApps.contains(where: { $0.bundleID == frontmostID }) {
            return .excludedApp
        }

        if settings.pauseDuringCalls {
            if SystemActivityMonitor.isCameraInUse() || SystemActivityMonitor.isMicrophoneInUse() {
                return .call
            }
        }

        if settings.pauseDuringScreenRecording, SystemActivityMonitor.isScreenRecording() {
            return .screenRecording
        }

        let caresAboutFullscreen = settings.pauseDuringPresentations
            || settings.pauseDuringGames
            || settings.pauseDuringFullscreenVideo
        guard caresAboutFullscreen, let app = frontmost, SystemActivityMonitor.isFullscreen(app) else {
            return nil
        }

        if settings.pauseDuringPresentations, SystemActivityMonitor.isPresentationApp(frontmostID) {
            return .presentation
        }
        if settings.pauseDuringGames, SystemActivityMonitor.isGame(app) {
            return .game
        }
        if settings.pauseDuringFullscreenVideo, SystemActivityMonitor.displaySleepPrevented() {
            return .fullscreenVideo
        }
        return nil
    }
}
