import AppKit

/// Entry point. Blink is a plain AppKit app with no storyboard, so the application
/// object and its delegate are created by hand.
@main
enum BlinkMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // `NSApplication.delegate` is weak; keep the delegate alive for the life of the run loop.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
