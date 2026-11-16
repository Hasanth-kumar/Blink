import SwiftUI
import AppKit

/// What the heads-up shows. The controller keeps this in step with the scheduler.
@MainActor
final class HeadsUpModel: ObservableObject {
    @Published var breakAt = Date()
    @Published var warningLength: TimeInterval = 60
    @Published var kind: BreakKind = .short
    @Published var breakDuration: TimeInterval = 20
    @Published var isWaitingForTyping = false
    @Published var snoozesLeft: Int?
    @Published var showSnoozesLeft = true
    @Published var canSnooze = true
    @Published var canSkip = true
    @Published var compact = false
    /// True while the pointer is over the card (or it was clicked open). Kept here rather
    /// than in `@State` so the project builds without Xcode's SwiftUI macro plug-in.
    @Published var isHovering = false

    var onStartNow: () -> Void = {}
    var onSnooze: (Int) -> Void = { _ in }
    var onSkip: () -> Void = {}
}

/// The small floating card that appears shortly before a break.
struct HeadsUpView: View {
    /// Size of the transparent panel that hosts the card. The card hugs the top-right corner.
    static let panelSize = CGSize(width: 408, height: 196)

    @ObservedObject var model: HeadsUpModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool {
        !model.compact || model.isHovering
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            card(now: context.date)
        }
        .padding(16)
        .frame(
            width: HeadsUpView.panelSize.width,
            height: HeadsUpView.panelSize.height,
            alignment: .topTrailing
        )
    }

    private func card(now: Date) -> some View {
        let remaining = max(0, model.breakAt.timeIntervalSince(now))
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                progressRing(remaining: remaining)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(remaining: remaining))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                    if isExpanded {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                if isExpanded {
                    Spacer(minLength: 0)
                }
            }

            if isExpanded {
                buttons
                footnote
            }
        }
        .padding(14)
        .frame(width: isExpanded ? 372 : nil, alignment: .leading)
        .background(
            shape
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 5)
        )
        .overlay(
            shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .contentShape(shape)
        .onHover { hovering in
            if reduceMotion {
                model.isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    model.isHovering = hovering
                }
            }
        }
        .onTapGesture {
            // A click also opens the compact card, in case hovering is not available.
            if model.compact, !model.isHovering {
                model.isHovering = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Upcoming break")
    }

    private func progressRing(remaining: TimeInterval) -> some View {
        let fraction: CGFloat
        if model.isWaitingForTyping || model.warningLength <= 0 {
            fraction = 0
        } else {
            fraction = CGFloat(min(1, max(0, remaining / model.warningLength)))
        }
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: model.kind == .long ? "figure.walk" : "eye")
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(width: 34, height: 34)
    }

    private func title(remaining: TimeInterval) -> String {
        if model.isWaitingForTyping {
            return "Break is ready"
        }
        return "Break in \(TimeFormat.clock(remaining))"
    }

    private var subtitle: String {
        if model.isWaitingForTyping {
            return "It will start when you pause typing."
        }
        let length = TimeFormat.spoken(model.breakDuration)
        return model.kind == .long ? "A \(length) long break is coming up." : "\(length) to rest your eyes."
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button("Start now") { model.onStartNow() }
                .buttonStyle(PillButtonStyle(prominent: true))
            Button("Snooze 1 min") { model.onSnooze(1) }
                .buttonStyle(PillButtonStyle())
                .disabled(!model.canSnooze)
            Button("Snooze 5 min") { model.onSnooze(5) }
                .buttonStyle(PillButtonStyle())
                .disabled(!model.canSnooze)
            if model.canSkip {
                Button("Skip") { model.onSkip() }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var footnote: some View {
        if model.showSnoozesLeft, let left = model.snoozesLeft {
            Text(snoozeText(left))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func snoozeText(_ left: Int) -> String {
        switch left {
        case 0: return "No snoozes left"
        case 1: return "1 snooze left"
        default: return "\(left) snoozes left"
        }
    }
}
