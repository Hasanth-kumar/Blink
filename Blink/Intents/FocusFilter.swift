import AppIntents

/// Lets a macOS Focus pause Blink.
///
/// The filter appears in System Settings → Focus → (a Focus) → Focus Filters → Add Filter.
/// macOS calls `perform()` whenever a Focus that uses the filter turns on, and calls it
/// again with every parameter at its default when that Focus turns off – which is why
/// "Pause break reminders" defaults to off.
struct BlinkFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set Blink Behaviour"

    static var description: IntentDescription? = IntentDescription(
        "Choose whether Blink keeps reminding you to take breaks while this Focus is on."
    )

    @Parameter(title: "Pause break reminders", default: false)
    var pauseBreaks: Bool

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource = pauseBreaks ? "Break reminders paused" : "Break reminders on"
        return DisplayRepresentation(title: "Blink", subtitle: subtitle)
    }

    func perform() async throws -> some IntentResult {
        let shouldPause = pauseBreaks
        await MainActor.run {
            BreakScheduler.shared.setFocusPause(shouldPause)
        }
        return .result()
    }
}
