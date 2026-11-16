import AppKit
import SwiftUI

// MARK: - Model

/// What the reminder on screen is showing. The controller fills this in; the views only read it.
@MainActor
final class NudgeModel: ObservableObject {
    @Published var script = NudgeScript(kind: .blink, blinkStyle: .squeeze, postureStyle: .rise)
    @Published var startedAt = Date()
    @Published var isPlaying = false
    @Published var diameter: CGFloat = 88
    @Published var position = NudgePosition.center
    @Published var dimsScreen = true
    @Published var caption = ""
    @Published var reduceMotion = false
    /// Space taken by the menu bar and the Dock, so a reminder at the top or bottom clears them.
    @Published var topInset: CGFloat = 0
    @Published var bottomInset: CGFloat = 0
}

// MARK: - Painting

/// Colours of the reminder. They are fixed rather than following light and dark mode: the
/// reminder sits on top of whatever happens to be on screen, so it carries its own contrast.
enum NudgePalette {
    static let ink = Color(hex: "#3A1820")
    static let faceTop = Color(hex: "#F0A957")
    static let faceBottom = Color(hex: "#EC6FB0")
}

/// Replays the shapes of a frame onto a canvas. All the movement is decided by `NudgeScript`;
/// this only draws what it is handed.
enum NudgePainter {
    static func paint(_ frame: NudgeFrame, diameter: CGFloat, in context: GraphicsContext) {
        for shape in frame.shapes {
            // Each shape gets its own copy of the context, so a clip or shadow never leaks into the next.
            var layer = context
            if let clip = shape.clip {
                layer.clip(to: Path(ellipseIn: clip))
            }
            if shape.castsShadow {
                layer.addFilter(
                    .shadow(color: Color.black.opacity(0.28), radius: diameter * 0.09, x: 0, y: diameter * 0.045)
                )
            }

            let path = NudgePainter.path(for: shape.geometry)
            let shading = NudgePainter.shading(for: shape.paint, filling: path)
            if shape.lineWidth > 0 {
                let style = StrokeStyle(lineWidth: CGFloat(shape.lineWidth), lineCap: .round, lineJoin: .round)
                layer.stroke(path, with: shading, style: style)
            } else {
                layer.fill(path, with: shading)
            }
        }
    }

    private static func path(for geometry: NudgeShape.Geometry) -> Path {
        switch geometry {
        case .capsule(let rect):
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
        case .roundedRect(let rect, let radius):
            let limit = min(rect.width, rect.height) / 2
            return Path(roundedRect: rect, cornerRadius: min(CGFloat(radius), limit))
        case .ellipse(let rect):
            return Path(ellipseIn: rect)
        case .polyline(let points):
            var path = Path()
            path.addLines(points)
            return path
        case .curve(let start, let control, let end):
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            return path
        }
    }

    private static func shading(for paint: NudgeShape.Paint, filling path: Path) -> GraphicsContext.Shading {
        switch paint {
        case .ink:
            return .color(NudgePalette.ink)
        case .face:
            // Warm at the top right, pink at the bottom left.
            let box = path.boundingRect
            return .linearGradient(
                Gradient(colors: [NudgePalette.faceTop, NudgePalette.faceBottom]),
                startPoint: CGPoint(x: box.maxX, y: box.minY),
                endPoint: CGPoint(x: box.minX, y: box.maxY)
            )
        }
    }
}

/// One frame of a reminder, as a view.
struct NudgeCanvas: View {
    let frame: NudgeFrame
    let diameter: CGFloat

    var body: some View {
        let frame = self.frame
        let diameter = self.diameter
        let size = NudgeScript.stageSize(diameter: diameter)
        return Canvas { context, _ in
            NudgePainter.paint(frame, diameter: diameter, in: context)
        }
        .frame(width: size.width, height: size.height)
        .opacity(frame.opacity)
        .accessibilityHidden(true)
    }
}

// MARK: - The reminder on screen

extension NudgePosition {
    var alignment: Alignment {
        switch self {
        case .center: return .center
        case .top: return .top
        case .bottom: return .bottom
        case .topRight: return .topTrailing
        }
    }
}

/// The full-screen, click-through layer a reminder plays on. It redraws every display
/// refresh while a reminder is playing and holds nothing at all in between.
struct NudgeStageView: View {
    /// How dark the screen gets behind a reminder when dimming is on.
    static let dimStrength = 0.16

    @ObservedObject var model: NudgeModel

    var body: some View {
        ZStack {
            if model.isPlaying {
                TimelineView(.animation) { context in
                    stage(at: context.date.timeIntervalSince(model.startedAt))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func stage(at time: TimeInterval) -> some View {
        let frame = model.script.frame(at: time, diameter: model.diameter, reduceMotion: model.reduceMotion)
        let dim = model.dimsScreen ? NudgeStageView.dimStrength * frame.dim : 0
        return ZStack(alignment: model.position.alignment) {
            Color.black.opacity(dim)
            NudgeCanvas(frame: frame, diameter: model.diameter)
                .overlay(alignment: .top) {
                    caption(opacity: frame.captionOpacity)
                }
                .padding(insets)
        }
    }

    /// Keeps a reminder at an edge clear of the menu bar and the Dock. A centred one needs no help.
    private var insets: EdgeInsets {
        if model.position == .center {
            return EdgeInsets()
        }
        return EdgeInsets(top: model.topInset, leading: 12, bottom: model.bottomInset, trailing: 12)
    }

    @ViewBuilder
    private func caption(opacity: Double) -> some View {
        if !model.caption.isEmpty {
            Text(model.caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .fixedSize()
                .opacity(opacity)
                .offset(y: model.script.captionOffset(diameter: model.diameter))
        }
    }
}

/// A small looping preview of a reminder, for the Settings window.
struct NudgePreview: View {
    private static let epoch = Date()
    private static let diameter: CGFloat = 46
    /// The breath between one run and the next.
    private static let pause = 0.9

    let script: NudgeScript
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stage = NudgeScript.stageSize(diameter: NudgePreview.diameter)
        return ZStack {
            if reduceMotion {
                // A still picture: the same one the reminder itself shows with Reduce Motion on.
                NudgeCanvas(
                    frame: script.frame(at: 1, diameter: NudgePreview.diameter, reduceMotion: true),
                    diameter: NudgePreview.diameter
                )
            } else {
                TimelineView(.animation) { context in
                    NudgeCanvas(frame: loopFrame(at: context.date), diameter: NudgePreview.diameter)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: stage.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the reminder animation")
    }

    /// The reminder starts from nothing and ends in nothing, so playing it again after a
    /// short pause loops without a visible seam.
    private func loopFrame(at date: Date) -> NudgeFrame {
        let loop = script.duration() + NudgePreview.pause
        let time = date.timeIntervalSince(NudgePreview.epoch).truncatingRemainder(dividingBy: loop)
        return script.frame(at: time, diameter: NudgePreview.diameter)
    }
}

// MARK: - Controller

/// Shows blink and posture reminders. They never take focus and never block a click.
@MainActor
final class NudgeController {
    private let settings: AppSettings
    private let model = NudgeModel()
    private var panel: PassivePanel?
    private var generation = 0

    init(settings: AppSettings) {
        self.settings = settings
        // Build both sounds up front, so the first reminder of the day starts without a pause.
        NudgeSoundPlayer.prepare(script(for: .blink))
        NudgeSoundPlayer.prepare(script(for: .posture))
    }

    func show(_ kind: NudgeKind) {
        guard let screen = NSScreen.withPointer else { return }
        let script = self.script(for: kind)
        let reduceMotion = Motion.isReduced
        generation += 1
        let token = generation

        model.script = script
        model.diameter = CGFloat(settings.nudgeSize.diameter)
        model.position = settings.nudgePosition
        model.dimsScreen = settings.nudgeDimsScreen
        model.caption = settings.nudgeShowsCaption ? caption(for: script) : ""
        model.reduceMotion = reduceMotion

        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel, on: screen)

        // Picture and sound start from the same instant; the script keeps them together from there.
        model.startedAt = Date()
        model.isPlaying = true
        panel.orderFrontRegardless()

        let soundOn = kind == .blink ? settings.blinkSoundEnabled : settings.postureSoundEnabled
        if soundOn {
            NudgeSoundPlayer.play(script, volume: settings.nudgeVolume, reduceMotion: reduceMotion)
        } else {
            NudgeSoundPlayer.stop()
        }

        let lifetime = script.duration(reduceMotion: reduceMotion) + 0.1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
            // Only take the panel down if no newer reminder has started in the meantime.
            guard let self = self, self.generation == token else { return }
            self.model.isPlaying = false
            panel.orderOut(nil)
        }
    }

    private func script(for kind: NudgeKind) -> NudgeScript {
        NudgeScript(kind: kind, blinkStyle: settings.blinkStyle, postureStyle: settings.postureStyle)
    }

    private func caption(for script: NudgeScript) -> String {
        switch script.figure {
        case .blink(let style): return style.caption
        case .posture(let style): return style.caption
        }
    }

    private func makePanel() -> PassivePanel {
        let panel = PassivePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.configureAsOverlay(level: .statusBar)
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: NudgeStageView(model: model))
        return panel
    }

    /// Covers the display the pointer is on. The panel is see-through and ignores the mouse,
    /// so all it adds to the screen is the reminder and, if enabled, a slight dimming.
    private func place(_ panel: NSPanel, on screen: NSScreen) {
        let frame = screen.frame
        let visible = screen.visibleFrame
        model.topInset = max(0, frame.maxY - visible.maxY)
        model.bottomInset = max(0, visible.minY - frame.minY)
        panel.setFrame(frame, display: true)
    }
}
