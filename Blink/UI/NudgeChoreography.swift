import Foundation

// The choreography of the blink and posture reminders.
//
// Everything here is plain arithmetic: given a moment in time it says what to draw and which
// sound cue falls where. It imports no UI framework, owns no timers and keeps no state, so the
// same moment always produces the same frame. `NudgeCanvas` paints the frames and
// `NudgeSoundSynth` renders the cues; both read their timing from this one place, which is what
// keeps picture and sound in step.

// MARK: - Easing

/// Easing curves. Each takes progress as 0…1 (anything outside is clamped) and returns eased progress.
enum Ease {
    static func clamp(_ x: Double) -> Double {
        min(1, max(0, x))
    }

    /// How far `time` is through a window that opens at `start` and lasts `duration`, as 0…1.
    static func progress(_ time: Double, from start: Double, lasting duration: Double) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return clamp((time - start) / duration)
    }

    static func smooth(_ x: Double) -> Double {
        let c = clamp(x)
        return c * c * (3 - 2 * c)
    }

    static func easeIn(_ x: Double) -> Double {
        let c = clamp(x)
        return c * c
    }

    static func easeOut(_ x: Double) -> Double {
        let c = 1 - clamp(x)
        return 1 - c * c
    }

    static func easeOutCubic(_ x: Double) -> Double {
        let c = 1 - clamp(x)
        return 1 - c * c * c
    }

    /// Eases out, travels a little past the target and settles back onto it.
    static func overshoot(_ x: Double) -> Double {
        let c = clamp(x) - 1
        let tension = 1.6
        return 1 + c * c * ((tension + 1) * c + tension)
    }

    static func mix(_ a: Double, _ b: Double, _ amount: Double) -> Double {
        a + (b - a) * amount
    }
}

// MARK: - Keyframes

/// A value that changes over time, written as a handful of keyframes.
///
///     Track(1).hold(until: 0.9).move(to: 0, by: 1.4)
///
/// reads "stay at 1 until 0.9 s, then ease to 0, arriving at 1.4 s".
struct Track: Sendable {
    enum Curve: Sendable {
        case linear
        case smooth
        case easeIn
        case easeOut
        case overshoot

        func apply(_ x: Double) -> Double {
            switch self {
            case .linear: return Ease.clamp(x)
            case .smooth: return Ease.smooth(x)
            case .easeIn: return Ease.easeIn(x)
            case .easeOut: return Ease.easeOut(x)
            case .overshoot: return Ease.overshoot(x)
            }
        }
    }

    private struct Key: Sendable {
        let time: Double
        let value: Double
        /// How the value travels from the previous keyframe to this one.
        let curve: Curve
    }

    private var keys: [Key]

    init(_ value: Double) {
        keys = [Key(time: 0, value: value, curve: .linear)]
    }

    /// Stays at the current value until `time`.
    func hold(until time: Double) -> Track {
        appending(Key(time: time, value: keys[keys.count - 1].value, curve: .linear))
    }

    /// Arrives at `value` at `time`, starting from wherever the previous keyframe left off.
    func move(to value: Double, by time: Double, _ curve: Curve = .smooth) -> Track {
        appending(Key(time: time, value: value, curve: curve))
    }

    func value(at time: Double) -> Double {
        var previous = keys[0]
        if time <= previous.time { return previous.value }
        for key in keys.dropFirst() {
            if time < key.time {
                let span = key.time - previous.time
                let x = span > 0 ? (time - previous.time) / span : 1
                return previous.value + (key.value - previous.value) * key.curve.apply(x)
            }
            previous = key
        }
        return previous.value
    }

    private func appending(_ key: Key) -> Track {
        var copy = self
        copy.keys.append(key)
        return copy
    }
}

// MARK: - Sound cues

/// One sound in a reminder, placed on the same clock as the animation.
struct NudgeSoundCue: Equatable, Sendable {
    enum Voice: Equatable, Sendable {
        /// The soft "bloop" as the reminder appears.
        case pop
        /// A tiny muted tap, used for a quick blink.
        case tick
        /// A bell-like note at this pitch (Hz) with a quiet fifth above it.
        case chime(Double)
        /// A single mellow note at this pitch (Hz).
        case note(Double)
        /// A breath-like tone that slides between two pitches (Hz) over `length` seconds.
        case glide(from: Double, to: Double, length: Double)
    }

    let time: Double
    let voice: Voice
    var gain = 1.0

    init(_ time: Double, _ voice: Voice, gain: Double = 1) {
        self.time = time
        self.voice = voice
        self.gain = gain
    }
}

// MARK: - What to draw

/// The pose of the little figure inside the puck at one moment.
enum NudgeGlyph: Equatable, Sendable {
    /// A pair of eyes. `open` 1 is a wide-open oval and 0 a closed line; `squeeze` 1 folds the
    /// closed line into "> <"; `curve` bends it, -1 into happy arcs and +1 into resting lids.
    case eyes(open: Double, squeeze: Double, curve: Double)
    /// A chevron that grows a stem and becomes an arrow. `spread` is how wide the head is.
    case arrow(stem: Double, spread: Double)
    /// A seated figure seen from the side. 0 is slouched, 1 is sitting tall.
    case sitter(upright: Double)
    /// Head and shoulders from the front. 1 is shoulders hunched up to the ears, 0 neutral, below 0 dropped.
    case shoulders(shrug: Double)
    /// Head, neck and shoulders from the front. -1 tilts the head to the left, +1 to the right.
    case neck(tilt: Double)
}

/// One thing to paint. Coordinates are in points inside the stage, origin at the top left.
struct NudgeShape: Equatable {
    enum Geometry: Equatable {
        /// A rectangle with fully rounded ends; a square one is a circle.
        case capsule(CGRect)
        /// A rectangle whose corners are rounded by `radius` points.
        case roundedRect(CGRect, radius: Double)
        case ellipse(CGRect)
        /// Connected straight lines, stroked with round ends and corners.
        case polyline([CGPoint])
        /// A quadratic curve, stroked with round ends.
        case curve(start: CGPoint, control: CGPoint, end: CGPoint)
    }

    enum Paint: Equatable {
        /// The dark colour of the ring and the figure.
        case ink
        /// The warm gradient of the face.
        case face
    }

    var geometry: Geometry
    var paint = Paint.ink
    /// Stroke width in points. 0 means the shape is filled instead.
    var lineWidth = 0.0
    /// An ellipse the shape is clipped to. The figure is clipped to the face so it never spills over the ring.
    var clip: CGRect?
    var castsShadow = false
}

/// Everything needed to draw one moment of a reminder.
struct NudgeFrame: Equatable {
    /// Painted in order, back to front.
    var shapes: [NudgeShape] = []
    /// 0…1: how far the screen dimming has faded in.
    var dim = 0.0
    /// Opacity of the whole stage. Only drops below 1 when Reduce Motion swaps movement for a fade.
    var opacity = 1.0
    /// 0…1: how visible the optional caption is.
    var captionOpacity = 0.0
}

// MARK: - The script

/// One reminder from start to finish: which figure it shows, how long it lasts,
/// what every frame looks like and where its sounds fall.
struct NudgeScript: Equatable, Sendable {
    enum Figure: Equatable, Sendable {
        case blink(BlinkNudgeStyle)
        case posture(PostureNudgeStyle)
    }

    let figure: Figure

    init(kind: NudgeKind, blinkStyle: BlinkNudgeStyle, postureStyle: PostureNudgeStyle) {
        switch kind {
        case .blink: figure = .blink(blinkStyle)
        case .posture: figure = .posture(postureStyle)
        }
    }

    var kind: NudgeKind {
        switch figure {
        case .blink: return .blink
        case .posture: return .posture
        }
    }

    /// A stable name for this reminder, used to keep its sound once it has been built.
    var identifier: String {
        switch figure {
        case .blink(let style): return "blink.\(style.rawValue)"
        case .posture(let style): return "posture.\(style.rawValue)"
        }
    }

    // MARK: Timing shared by every style (seconds from the moment the reminder appears)

    /// The dark disc grows from a dot to full size.
    static let enterDuration = 0.46
    /// The face opens from the centre of the disc, leaving a ring.
    static let revealStart = 0.38
    static let revealDuration = 0.14
    /// The figure pops in just behind the face.
    static let glyphPopStart = 0.40
    static let glyphPopDuration = 0.30
    /// At the end the face closes back into a disc, which then shrinks away.
    static let concealDuration = 0.13
    static let exitDuration = 0.42
    /// With Reduce Motion the reminder is one still picture that fades in and out.
    static let reducedDuration = 2.6
    /// Ring thickness as a fraction of the puck's radius.
    static let ringWidth = 0.14

    /// How long the reminder is on screen.
    func duration(reduceMotion: Bool = false) -> Double {
        if reduceMotion { return NudgeScript.reducedDuration }
        return timeline.actionEnd + NudgeScript.concealDuration + NudgeScript.exitDuration
    }

    /// The sounds that go with the reminder, on the animation's clock.
    func cues(reduceMotion: Bool = false) -> [NudgeSoundCue] {
        if reduceMotion { return [NudgeSoundCue(0, .pop)] }
        return timeline.cues
    }

    // MARK: Layout

    /// The area a reminder is drawn in. It leaves room for the puck to climb and for its shadow.
    static func stageSize(diameter: CGFloat) -> CGSize {
        let d = Double(diameter)
        return CGSize(width: d * 2.2, height: d * 3.0)
    }

    /// Distance from the top of the stage to where a caption should start: just below the puck's lowest point.
    func captionOffset(diameter: CGFloat) -> CGFloat {
        let d = Double(diameter)
        return CGFloat(restCentre(diameter: d) + d * 0.5 + d * 0.2)
    }

    /// Height of the puck's centre before it moves. The climb is centred in the stage, so the
    /// reminder as a whole sits around the point it is anchored to.
    private func restCentre(diameter d: Double) -> Double {
        d * 3.0 / 2 + timeline.rise * d / 2
    }

    // MARK: Frames

    /// What the reminder looks like `time` seconds after it appeared.
    func frame(at time: Double, diameter: CGFloat, reduceMotion: Bool = false) -> NudgeFrame {
        let line = timeline
        let total = duration(reduceMotion: reduceMotion)
        var frame = NudgeFrame()
        guard time >= 0, time < total else { return frame }

        frame.dim = min(
            Ease.smooth(time / 0.35),
            1 - Ease.smooth((time - (total - 0.45)) / 0.40)
        )
        frame.captionOpacity = min(
            Ease.smooth((time - 0.45) / 0.30),
            1 - Ease.smooth((time - (total - 0.75)) / 0.30)
        )

        var scale = 1.0
        var reveal = 1.0
        var glyphScale = 1.0
        var topClimb = line.rise
        var bottomClimb = line.rise
        let glyph: NudgeGlyph

        if reduceMotion {
            frame.opacity = min(
                Ease.smooth(time / 0.25),
                1 - Ease.smooth((time - (total - 0.30)) / 0.30)
            )
            glyph = line.glyph(line.poster)
        } else {
            let exitStart = line.actionEnd + NudgeScript.concealDuration
            if time < NudgeScript.enterDuration {
                // A quick start that settles gently, like a drop landing.
                let settled = 1 - exp(-NudgeScript.enterDuration / 0.12)
                scale = (1 - exp(-time / 0.12)) / settled
            } else if time > exitStart {
                let leaving = Ease.progress(time, from: exitStart, lasting: NudgeScript.exitDuration)
                scale = pow(1 - leaving, 1.15)
            }

            if time > line.actionEnd {
                let closing = Ease.progress(time, from: line.actionEnd, lasting: NudgeScript.concealDuration)
                reveal = 1 - Ease.easeIn(closing)
                glyphScale = reveal
            } else {
                let opening = Ease.progress(time, from: NudgeScript.revealStart, lasting: NudgeScript.revealDuration)
                reveal = Ease.easeOut(opening)
                let pop = Ease.progress(time, from: NudgeScript.glyphPopStart, lasting: NudgeScript.glyphPopDuration)
                glyphScale = 0.35 + 0.65 * Ease.overshoot(pop)
            }

            // The face leads the climb and the body catches up, so the puck stretches like
            // someone straightening their back before it settles higher up.
            let topProgress = Ease.progress(time, from: line.riseStart, lasting: line.topDuration)
            let bottomProgress = Ease.progress(
                time,
                from: line.riseStart + line.bottomDelay,
                lasting: line.bottomDuration
            )
            topClimb = line.rise * Ease.easeOutCubic(topProgress)
            bottomClimb = line.rise * Ease.easeOut(bottomProgress)
            glyph = line.glyph(time)
        }

        let d = Double(diameter)
        let stage = NudgeScript.stageSize(diameter: diameter)
        let centreX = Double(stage.width) / 2
        let rest = restCentre(diameter: d)
        let radius = d / 2 * scale
        guard radius > 0.25 else { return frame }

        let topY = rest - topClimb * d
        let bottomY = rest - bottomClimb * d
        let body = CGRect(
            x: centreX - radius,
            y: topY - radius,
            width: radius * 2,
            height: (bottomY - topY) + radius * 2
        )
        frame.shapes.append(NudgeShape(geometry: .capsule(body), castsShadow: true))

        let faceRadius = radius * (1 - NudgeScript.ringWidth) * reveal
        guard faceRadius > 0.3 else { return frame }
        let face = CGRect(
            x: centreX - faceRadius,
            y: topY - faceRadius,
            width: faceRadius * 2,
            height: faceRadius * 2
        )
        frame.shapes.append(NudgeShape(geometry: .ellipse(face), paint: .face))

        let pen = GlyphPen(
            centre: CGPoint(x: centreX, y: topY),
            unit: radius * (1 - NudgeScript.ringWidth) * glyphScale,
            clip: face
        )
        frame.shapes.append(contentsOf: pen.shapes(for: glyph))
        return frame
    }
}

// MARK: - Timelines

extension NudgeScript {
    /// When things happen for one style, in seconds from the moment the reminder appears.
    private struct Timeline: Sendable {
        /// The figure has finished here, and the face starts to close.
        var actionEnd: Double
        /// A moment that sums the reminder up in one still picture (used with Reduce Motion).
        var poster: Double
        /// How far the puck climbs, in diameters.
        var rise = 0.0
        var riseStart = 0.0
        /// How long the face takes to reach the top.
        var topDuration = 0.88
        /// How long the body waits before following, and how long it then takes.
        var bottomDelay = 0.20
        var bottomDuration = 0.80
        var glyph: @Sendable (Double) -> NudgeGlyph
        var cues: [NudgeSoundCue]
    }

    private var timeline: Timeline {
        switch figure {
        case .blink(.squeeze): return NudgeScript.blinkSqueeze
        case .blink(.natural): return NudgeScript.blinkNatural
        case .blink(.slow): return NudgeScript.blinkSlow
        case .posture(.rise): return NudgeScript.postureRise
        case .posture(.sitTall): return NudgeScript.postureSitTall
        case .posture(.shoulders): return NudgeScript.postureShoulders
        case .posture(.neck): return NudgeScript.postureNeck
        }
    }

    // MARK: Blink

    /// The classic: eyes screwed shut, two quick releases, then a contented smile.
    private static let blinkSqueeze: Timeline = {
        let squeeze = Track(1)
            .hold(until: 0.74).move(to: 0, by: 0.80)
            .hold(until: 0.86).move(to: 1, by: 0.92)
            .hold(until: 1.02).move(to: 0, by: 1.08)
            .hold(until: 1.14).move(to: 1, by: 1.20)
            .hold(until: 1.40).move(to: 0, by: 1.47)
        let curve = Track(0)
            .hold(until: 1.47).move(to: -1, by: 1.64, .overshoot)
        return Timeline(
            actionEnd: 2.20,
            poster: 1.90,
            glyph: { time in
                .eyes(open: 0, squeeze: squeeze.value(at: time), curve: curve.value(at: time))
            },
            cues: [
                NudgeSoundCue(0.00, .pop),
                NudgeSoundCue(0.77, .tick),
                NudgeSoundCue(1.05, .tick),
                NudgeSoundCue(1.47, .chime(659.26))
            ]
        )
    }()

    /// Open eyes that blink the way people do: a fast close, a slower open, three times.
    private static let blinkNatural: Timeline = {
        let open = Track(1)
            .hold(until: 0.86).move(to: 0, by: 0.94, .easeIn)
            .hold(until: 0.98).move(to: 1, by: 1.13, .easeOut)
            .hold(until: 1.62).move(to: 0, by: 1.70, .easeIn)
            .hold(until: 1.74).move(to: 1, by: 1.89, .easeOut)
            .hold(until: 2.02).move(to: 0, by: 2.10, .easeIn)
            .hold(until: 2.14).move(to: 1, by: 2.29, .easeOut)
        return Timeline(
            actionEnd: 2.62,
            poster: 0.96,
            glyph: { time in
                .eyes(open: open.value(at: time), squeeze: 0, curve: 0)
            },
            cues: [
                NudgeSoundCue(0.00, .pop),
                NudgeSoundCue(0.90, .tick),
                NudgeSoundCue(1.66, .tick),
                NudgeSoundCue(2.06, .tick)
            ]
        )
    }()

    /// Two slow, complete blinks to follow along with: close, rest, open, pause.
    private static let blinkSlow: Timeline = {
        let open = Track(1)
            .hold(until: 0.90).move(to: 0, by: 1.45)
            .hold(until: 2.33).move(to: 1, by: 2.90)
            .hold(until: 3.35).move(to: 0, by: 3.90)
            .hold(until: 4.78).move(to: 1, by: 5.35)
        // Once shut, the lids relax into a soft curve, and straighten again just before opening.
        let curve = Track(0)
            .hold(until: 1.45).move(to: 0.75, by: 1.68)
            .hold(until: 2.12).move(to: 0, by: 2.33)
            .hold(until: 3.90).move(to: 0.75, by: 4.13)
            .hold(until: 4.57).move(to: 0, by: 4.78)
        return Timeline(
            actionEnd: 5.70,
            poster: 1.90,
            glyph: { time in
                .eyes(open: open.value(at: time), squeeze: 0, curve: curve.value(at: time))
            },
            cues: [
                NudgeSoundCue(0.00, .pop),
                NudgeSoundCue(0.90, .glide(from: 523.25, to: 392.00, length: 0.55)),
                NudgeSoundCue(2.33, .glide(from: 392.00, to: 523.25, length: 0.57)),
                NudgeSoundCue(3.35, .glide(from: 523.25, to: 392.00, length: 0.55)),
                NudgeSoundCue(4.78, .glide(from: 392.00, to: 523.25, length: 0.57))
            ]
        )
    }()

    // MARK: Posture

    /// The classic: a chevron that stretches the whole puck upward and becomes an arrow.
    private static let postureRise: Timeline = {
        let stem = Track(0)
            .hold(until: 0.91).move(to: 1, by: 1.12)
        let spread = Track(1)
            .hold(until: 0.91).move(to: 0.2, by: 1.05)
            .move(to: 0, by: 1.12)
            .hold(until: 1.16).move(to: 1, by: 1.47, .overshoot)
        return Timeline(
            actionEnd: 2.20,
            poster: 2.00,
            rise: 0.78,
            riseStart: 0.91,
            glyph: { time in
                .arrow(stem: stem.value(at: time), spread: spread.value(at: time))
            },
            cues: [
                NudgeSoundCue(0.00, .pop),
                NudgeSoundCue(0.91, .glide(from: 329.63, to: 587.33, length: 0.42)),
                NudgeSoundCue(1.30, .chime(783.99))
            ]
        )
    }()

    /// A slouched figure sinks a little further, then sits up tall.
    private static let postureSitTall: Timeline = {
        let upright = Track(0)
            .hold(until: 0.72).move(to: -0.12, by: 1.02)
            .move(to: 1, by: 1.72, .overshoot)
        return Timeline(
            actionEnd: 2.80,
            poster: 2.40,
            rise: 0.22,
            riseStart: 1.06,
            topDuration: 0.70,
            bottomDelay: 0.14,
            bottomDuration: 0.70,
            glyph: { time in
                .sitter(upright: upright.value(at: time))
            },
            cues: [
                NudgeSoundCue(0.00, .pop),
                NudgeSoundCue(1.02, .glide(from: 293.66, to: 440.00, length: 0.62)),
                NudgeSoundCue(1.60, .chime(659.26))
            ]
        )
    }()

    /// Shoulders lift to the ears, hold, then drop and loosen. Twice.
    private static let postureShoulders: Timeline = {
        let shrug = Track(0)
            .hold(until: 0.85).move(to: 1, by: 1.30, .easeOut)
            .hold(until: 1.65).move(to: -0.35, by: 2.15, .overshoot)
            .hold(until: 2.45).move(to: 1, by: 2.90, .easeOut)
            .hold(until: 3.25).move(to: -0.35, by: 3.75, .overshoot)
        return Timeline(
            actionEnd: 4.35,
            poster: 4.00,
            glyph: { time in
                .shoulders(shrug: shrug.value(at: time))
            },
            cues: [
                NudgeSoundCue(0.00, .pop),
                NudgeSoundCue(0.85, .glide(from: 349.23, to: 466.16, length: 0.45)),
                NudgeSoundCue(1.65, .glide(from: 466.16, to: 311.13, length: 0.50)),
                NudgeSoundCue(2.45, .glide(from: 349.23, to: 466.16, length: 0.45)),
                NudgeSoundCue(3.25, .glide(from: 466.16, to: 311.13, length: 0.50))
            ]
        )
    }()

    /// The head tips slowly toward one shoulder, then the other, and returns to the middle.
    private static let postureNeck: Timeline = {
        let tilt = Track(0)
            .hold(until: 0.85).move(to: -1, by: 1.45)
            .hold(until: 1.95).move(to: 1, by: 2.85)
            .hold(until: 3.35).move(to: 0, by: 3.95)
        return Timeline(
            actionEnd: 4.35,
            poster: 1.70,
            glyph: { time in
                .neck(tilt: tilt.value(at: time))
            },
            cues: [
                NudgeSoundCue(0.00, .pop),
                NudgeSoundCue(0.88, .note(440.00)),
                NudgeSoundCue(2.00, .note(493.88)),
                NudgeSoundCue(3.38, .note(587.33))
            ]
        )
    }()
}

// MARK: - Drawing the figures

/// Turns a pose into shapes. Poses are described on a face one unit in radius, centred on (0, 0)
/// with y pointing down; the pen scales that onto the stage.
private struct GlyphPen {
    let centre: CGPoint
    /// Points per unit: the radius of the face, times the figure's pop-in scale.
    let unit: Double
    let clip: CGRect

    func shapes(for glyph: NudgeGlyph) -> [NudgeShape] {
        switch glyph {
        case .eyes(let open, let squeeze, let curve):
            return [
                eye(side: -1, open: open, squeeze: squeeze, curve: curve),
                eye(side: 1, open: open, squeeze: squeeze, curve: curve)
            ]

        case .arrow(let stem, let spread):
            let apexY = Ease.mix(-0.16, -0.42, stem)
            let armX = 0.31 * spread
            let armY = 0.31 * (0.30 + 0.70 * min(spread, 1))
            var shapes = [
                line([point(-armX, apexY + armY), point(0, apexY), point(armX, apexY + armY)], width: 0.15)
            ]
            if stem > 0.01 {
                shapes.append(line([point(0, apexY), point(0, apexY + 0.84 * stem)], width: 0.15))
            }
            return shapes

        case .sitter(let upright):
            // Seen from the side, facing right: a spine from the hips to the neck, a head, and a
            // thigh and shin to show the figure is sitting. Slouched, the back rounds and the
            // head hangs forward; upright, the spine straightens and the head sits above the hips.
            let hip = point(-0.16, 0.44)
            let neck = point(Ease.mix(0.10, -0.16, upright), Ease.mix(-0.02, -0.20, upright))
            let bend = point(Ease.mix(-0.52, -0.16, upright), 0.12)
            let headX = Ease.mix(0.27, -0.14, upright)
            let headY = Ease.mix(-0.17, -0.44, upright)
            return [
                arc(from: hip, control: bend, to: neck, width: 0.13),
                line([hip, point(0.34, 0.44), point(0.36, 0.68)], width: 0.13),
                dot(headX, headY, radius: 0.15)
            ]

        case .shoulders(let shrug):
            // Seen from the front: a head, a neck and the top of the body. Shrugging lifts the
            // shoulders to the ears and squares them off; letting go drops them lower and
            // rounder than where they began.
            let top = 0.20 - 0.18 * shrug
            return [
                line([point(0, -0.12), point(0, top + 0.12)], width: 0.15),
                torso(top: top, corner: 0.30 - 0.14 * shrug),
                dot(0, -0.36, radius: 0.29)
            ]

        case .neck(let tilt):
            // The head tips toward one shoulder on the base of the neck, like an upside-down pendulum.
            let angle = tilt * 22 * Double.pi / 180
            let pivotY = 0.34
            let headX = 0.70 * sin(angle)
            let headY = pivotY - 0.70 * cos(angle)
            let neckX = 0.46 * sin(angle)
            let neckY = pivotY - 0.46 * cos(angle)
            return [
                line([point(0, pivotY), point(neckX, neckY)], width: 0.15),
                torso(top: 0.24, corner: 0.32),
                dot(headX, headY, radius: 0.29)
            ]
        }
    }

    /// One eye. Every state passes through the same closed line, so any change between
    /// open, squeezed and curved is continuous.
    private func eye(side: Double, open: Double, squeeze: Double, curve: Double) -> NudgeShape {
        let x = 0.36 * side
        let y = -0.04
        let half = 0.12
        let stroke = 0.095

        if open > 0.01 {
            // An oval that flattens into the closed line as the lid comes down.
            let width = Ease.mix(half * 2 + stroke, 0.25, open)
            let height = Ease.mix(stroke, 0.40, open)
            let rect = CGRect(
                x: Double(centre.x) + (x - width / 2) * unit,
                y: Double(centre.y) + (y - height / 2) * unit,
                width: width * unit,
                height: height * unit
            )
            return NudgeShape(geometry: .capsule(rect), clip: clip)
        }

        if squeeze > 0.01 {
            // ">" on the left and "<" on the right: both point at the nose.
            let outer = x + half * side
            let inner = x - half * side
            let reach = 0.17 * squeeze
            return line([point(outer, y - reach), point(inner, y), point(outer, y + reach)], width: stroke)
        }

        // A closed lid. Negative `curve` lifts the middle into a smiling arc, positive lets it sag.
        let height = -curve * 0.16
        return arc(
            from: point(x - half, y + height / 2),
            control: point(x, y - height * 1.5),
            to: point(x + half, y + height / 2),
            width: stroke
        )
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: Double(centre.x) + x * unit, y: Double(centre.y) + y * unit)
    }

    private func line(_ points: [CGPoint], width: Double) -> NudgeShape {
        NudgeShape(geometry: .polyline(points), lineWidth: width * unit, clip: clip)
    }

    private func arc(from start: CGPoint, control: CGPoint, to end: CGPoint, width: Double) -> NudgeShape {
        NudgeShape(geometry: .curve(start: start, control: control, end: end), lineWidth: width * unit, clip: clip)
    }

    /// The top of a body: a wide block with rounded shoulders that runs off the bottom of the face.
    private func torso(top: Double, corner: Double) -> NudgeShape {
        let halfWidth = 0.56
        let rect = CGRect(
            x: Double(centre.x) - halfWidth * unit,
            y: Double(centre.y) + top * unit,
            width: halfWidth * 2 * unit,
            height: 1.4 * unit
        )
        return NudgeShape(geometry: .roundedRect(rect, radius: max(0, corner) * unit), clip: clip)
    }

    private func dot(_ x: Double, _ y: Double, radius: Double) -> NudgeShape {
        let rect = CGRect(
            x: Double(centre.x) + (x - radius) * unit,
            y: Double(centre.y) + (y - radius) * unit,
            width: radius * 2 * unit,
            height: radius * 2 * unit
        )
        return NudgeShape(geometry: .ellipse(rect), clip: clip)
    }
}
