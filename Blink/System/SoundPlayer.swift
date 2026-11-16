import AppKit

/// Plays the chime at the end of a break, using the sounds that ship with macOS.
@MainActor
enum SoundPlayer {
    /// Names of system sounds found in /System/Library/Sounds.
    static let availableSounds = [
        "Glass", "Ping", "Purr", "Tink", "Pop", "Hero", "Submarine", "Blow", "Bottle", "Funk", "Morse", "Frog"
    ]

    private static var current: NSSound?

    static func play(name: String, volume: Double) {
        guard !name.isEmpty, let systemSound = NSSound(named: name) else { return }
        // `NSSound(named:)` hands back a shared instance; copy it so the volume
        // change does not leak into other uses of the same sound.
        let sound = (systemSound.copy() as? NSSound) ?? systemSound
        sound.volume = Float(min(max(volume, 0), 1))
        current?.stop()
        current = sound
        sound.play()
    }
}
