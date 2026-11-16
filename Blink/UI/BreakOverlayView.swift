import SwiftUI
import AppKit

/// What the break screen shows. Every display's overlay reads the same model,
/// so all countdowns stay in step.
@MainActor
final class BreakOverlayModel: ObservableObject {
    @Published var kind: BreakKind = .short
    @Published var startedAt = Date()
    @Published var endsAt = Date()
    @Published var message = ""
    @Published var allowSkip = true
    @Published var isPreview = false
    @Published var backgroundImage: NSImage?

    var onSkip: () -> Void = {}
}

/// The full-screen break view.
struct BreakOverlayView: View {
    @ObservedObject var model: BreakOverlayModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Text colour: the blurred background follows light/dark mode, the others are always dark.
    private var foreground: Color {
        settings.backgroundStyle == .blur ? Color.primary : Color.white
    }

    private var selectedGradient: GradientPreset {
        GradientPreset(rawValue: settings.gradientPreset) ?? .dusk
    }

    private var secondary: Color {
        foreground.opacity(0.7)
    }

    var body: some View {
        ZStack {
            background
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                content(now: context.date)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Background

    @ViewBuilder
    private var background: some View {
        switch settings.backgroundStyle {
        case .blur:
            VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
        case .solid:
            Color(hex: settings.solidColorHex)
        case .gradient:
            selectedGradient.gradient
        case .image:
            imageBackground
        }
    }

    @ViewBuilder
    private var imageBackground: some View {
        if let image = model.backgroundImage {
            GeometryReader { proxy in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            // A dark scrim keeps the text readable on any photo.
            .overlay(Color.black.opacity(0.45))
        } else {
            GradientPreset.dusk.gradient
        }
    }

    // MARK: Content

    private func content(now: Date) -> some View {
        let total = max(1, model.endsAt.timeIntervalSince(model.startedAt))
        let remaining = max(0, model.endsAt.timeIntervalSince(now))
        let progress = CGFloat(min(1, max(0, remaining / total)))

        return VStack(spacing: 26) {
            Image(systemName: model.kind == .long ? "figure.walk" : "eye")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(secondary)
                .accessibilityHidden(true)

            Text(model.message)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
                .frame(maxWidth: 780)

            ZStack {
                Circle()
                    .stroke(foreground.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(foreground.opacity(0.85), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.25), value: progress)
                Text(TimeFormat.clock(remaining))
                    .font(.system(size: 54, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(foreground)
            }
            .frame(width: 210, height: 210)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time left")
            .accessibilityValue(TimeFormat.spoken(remaining.rounded(.up)))

            Text(caption(total: total))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(secondary)

            if model.allowSkip {
                VStack(spacing: 8) {
                    Button(action: model.onSkip) {
                        Text(model.isPreview ? "Close preview" : "Skip break")
                    }
                    .buttonStyle(OverlayButtonStyle(tint: foreground))
                    .keyboardShortcut(.cancelAction)

                    Text("or press Esc")
                        .font(.system(size: 12))
                        .foregroundStyle(secondary)
                }
                .padding(.top, 6)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func caption(total: TimeInterval) -> String {
        if model.isPreview {
            return "Preview"
        }
        let length = TimeFormat.spoken(total)
        return model.kind == .long ? "Long break · \(length)" : "Eye break · \(length)"
    }
}
