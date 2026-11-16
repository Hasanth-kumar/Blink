import AppKit

/// Turns a reminder's sound cues into audio.
///
/// Nothing is recorded or bundled: every sound is a few soft sine tones worked out in code and
/// laid out on the animation's own clock. One buffer covers the whole reminder, so starting it
/// together with the animation keeps every cue in step for as long as the reminder runs.
enum NudgeSoundSynth {
    static let sampleRate = 44_100.0

    /// A complete WAV file (16-bit, mono) for `cues`, long enough for a reminder lasting `duration` seconds.
    static func wav(for cues: [NudgeSoundCue], duration: Double) -> Data {
        // Room for the last note to ring out after the picture has gone.
        let tail = 1.2
        let count = max(1, Int((duration + tail) * sampleRate))
        var samples = [Double](repeating: 0, count: count)
        for cue in cues {
            render(cue, into: &samples)
        }
        soften(&samples)
        return encode(samples)
    }

    // MARK: Voices

    private static func render(_ cue: NudgeSoundCue, into samples: inout [Double]) {
        switch cue.voice {
        case .pop:
            // A rounded "bloop": a short upward bend that is gone within a tenth of a second.
            addTone(&samples, at: cue.time, from: 250, to: 420, length: 0.18, gain: 0.30 * cue.gain,
                    envelope: struck(attack: 0.006, decay: 0.036))

        case .tick:
            // A muted tap, low enough to feel like an eyelid rather than a click.
            addTone(&samples, at: cue.time, from: 620, to: 540, length: 0.14, gain: 0.20 * cue.gain,
                    envelope: struck(attack: 0.003, decay: 0.024))

        case .chime(let root):
            // A small bell: the note, a quieter fifth above it and a trace of the octave.
            addTone(&samples, at: cue.time, from: root, to: root, length: 1.5, gain: 0.24 * cue.gain,
                    envelope: struck(attack: 0.006, decay: 0.30))
            addTone(&samples, at: cue.time, from: root * 1.5, to: root * 1.5, length: 1.1, gain: 0.10 * cue.gain,
                    envelope: struck(attack: 0.008, decay: 0.22))
            addTone(&samples, at: cue.time, from: root * 2, to: root * 2, length: 0.6, gain: 0.035 * cue.gain,
                    envelope: struck(attack: 0.004, decay: 0.12))

        case .note(let pitch):
            addTone(&samples, at: cue.time, from: pitch, to: pitch, length: 1.3, gain: 0.22 * cue.gain,
                    envelope: struck(attack: 0.010, decay: 0.26))
            addTone(&samples, at: cue.time, from: pitch * 2, to: pitch * 2, length: 0.6, gain: 0.03 * cue.gain,
                    envelope: struck(attack: 0.006, decay: 0.12))

        case .glide(let from, let to, let length):
            // A breath: swells in, slides to the new pitch and fades, with no hard edge anywhere.
            addTone(&samples, at: cue.time, from: from, to: to, length: length, gain: 0.17 * cue.gain,
                    envelope: swell(over: length))
            addTone(&samples, at: cue.time, from: from * 2, to: to * 2, length: length, gain: 0.02 * cue.gain,
                    envelope: swell(over: length))
        }
    }

    /// The loudness of a struck note: a fast rise and a natural, ever-slowing decay.
    private static func struck(attack: Double, decay: Double) -> (Double) -> Double {
        return { time in
            min(time / attack, 1) * exp(-time / decay)
        }
    }

    /// The loudness of a breath-like tone: it eases in over the first third and out over the rest.
    private static func swell(over length: Double) -> (Double) -> Double {
        return { time in
            let rise = Ease.smooth(time / (length * 0.35))
            let fall = 1 - Ease.smooth((time - length * 0.45) / (length * 0.55))
            return rise * fall
        }
    }

    /// Adds one sine tone to the buffer. The pitch slides from `startPitch` to `endPitch`
    /// (equal values give a steady note) and `envelope` shapes its loudness over time.
    private static func addTone(
        _ samples: inout [Double],
        at start: Double,
        from startPitch: Double,
        to endPitch: Double,
        length: Double,
        gain: Double,
        envelope: (Double) -> Double
    ) {
        let first = Int(start * sampleRate)
        let count = Int(length * sampleRate)
        guard count > 1, startPitch > 0, endPitch > 0 else { return }

        let ratio = endPitch / startPitch
        var phase = 0.0
        for offset in 0..<count {
            let index = first + offset
            if index >= samples.count { break }

            // Slide along a musical (exponential) path, easing in and out of the movement.
            let progress = Ease.smooth(Double(offset) / Double(count))
            let pitch = ratio == 1 ? startPitch : startPitch * pow(ratio, progress)
            phase += 2 * Double.pi * pitch / sampleRate
            if index < 0 { continue }

            let time = Double(offset) / sampleRate
            // A few milliseconds of fade at the very end, so a tone never stops with a click.
            let release = min(1, (length - time) / 0.012)
            samples[index] += sin(phase) * gain * envelope(time) * release
        }
    }

    // MARK: Output

    /// Brings every reminder to the same comfortable level: loud enough to notice at full volume,
    /// with plenty of headroom so overlapping tones can never clip.
    private static func soften(_ samples: inout [Double]) {
        var peak = 0.0
        for sample in samples {
            peak = max(peak, abs(sample))
        }
        guard peak > 0 else { return }
        let scale = 0.6 / peak
        for index in samples.indices {
            samples[index] *= scale
        }
    }

    private static func encode(_ samples: [Double]) -> Data {
        let rate = Int(sampleRate)
        let dataSize = samples.count * 2
        var bytes = [UInt8]()
        bytes.reserveCapacity(44 + dataSize)

        func putText(_ text: String) {
            bytes.append(contentsOf: Array(text.utf8))
        }
        func put32(_ value: Int) {
            let bits = UInt32(truncatingIfNeeded: value)
            bytes.append(UInt8(bits & 0xFF))
            bytes.append(UInt8((bits >> 8) & 0xFF))
            bytes.append(UInt8((bits >> 16) & 0xFF))
            bytes.append(UInt8((bits >> 24) & 0xFF))
        }
        func put16(_ value: Int) {
            let bits = UInt16(truncatingIfNeeded: value)
            bytes.append(UInt8(bits & 0xFF))
            bytes.append(UInt8((bits >> 8) & 0xFF))
        }

        putText("RIFF")
        put32(36 + dataSize)
        putText("WAVE")
        putText("fmt ")
        put32(16)          // size of the format block
        put16(1)           // uncompressed PCM
        put16(1)           // mono
        put32(rate)
        put32(rate * 2)    // bytes per second
        put16(2)           // bytes per sample
        put16(16)          // bits per sample
        putText("data")
        put32(dataSize)

        for sample in samples {
            let clipped = max(-1, min(1, sample))
            put16(Int((clipped * 32_767).rounded()))
        }
        return Data(bytes)
    }
}

// MARK: - Playback

/// Plays a reminder's sound. Each sound is built once and kept, since it never changes.
@MainActor
enum NudgeSoundPlayer {
    private static var cache: [String: Data] = [:]
    private static var current: NSSound?

    /// Builds the sound ahead of time, so the first reminder starts without a pause.
    static func prepare(_ script: NudgeScript, reduceMotion: Bool = false) {
        _ = data(for: script, reduceMotion: reduceMotion)
    }

    /// Starts the sound now. Call it at the same moment the animation starts.
    static func play(_ script: NudgeScript, volume: Double, reduceMotion: Bool = false) {
        stop()
        let level = min(max(volume, 0), 1)
        guard level > 0, let sound = NSSound(data: data(for: script, reduceMotion: reduceMotion)) else { return }
        sound.volume = Float(level)
        current = sound
        sound.play()
    }

    static func stop() {
        current?.stop()
        current = nil
    }

    private static func data(for script: NudgeScript, reduceMotion: Bool) -> Data {
        let key = script.identifier + (reduceMotion ? ".still" : "")
        if let cached = cache[key] {
            return cached
        }
        let data = NudgeSoundSynth.wav(
            for: script.cues(reduceMotion: reduceMotion),
            duration: script.duration(reduceMotion: reduceMotion)
        )
        cache[key] = data
        return data
    }
}
