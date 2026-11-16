import AppIntents

// Actions for the Shortcuts app. They run inside Blink, so they act on the live scheduler.

struct StartBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Break"
    static var description = IntentDescription("Starts a Blink break right away.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            BreakScheduler.shared.startBreakNow()
        }
        return .result()
    }
}

struct SkipBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Break"
    static var description = IntentDescription("Skips the current Blink break, or the next one if none is showing.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            BreakScheduler.shared.skip()
        }
        return .result()
    }
}

struct PauseBreaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Breaks"
    static var description = IntentDescription("Pauses Blink for a number of minutes. Use 0 to pause until you resume.")

    @Parameter(title: "Minutes", default: 30)
    var minutes: Int

    func perform() async throws -> some IntentResult {
        let length = minutes
        await MainActor.run {
            if length > 0 {
                BreakScheduler.shared.pause(.minutes(length))
            } else {
                BreakScheduler.shared.pause(.indefinitely)
            }
        }
        return .result()
    }
}

struct ResumeBreaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Breaks"
    static var description = IntentDescription("Resumes Blink after a pause.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            BreakScheduler.shared.resume()
        }
        return .result()
    }
}
