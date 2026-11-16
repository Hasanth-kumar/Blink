import SwiftUI
import AppKit

/// Built-in gradients for the break screen.
enum GradientPreset: String, CaseIterable, Identifiable {
    case dusk
    case ocean
    case forest
    case ember
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dusk: return "Dusk"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .ember: return "Ember"
        case .graphite: return "Graphite"
        }
    }

    var colors: [Color] {
        switch self {
        case .dusk: return [Color(hex: "#23254F"), Color(hex: "#5B4580"), Color(hex: "#B56A82")]
        case .ocean: return [Color(hex: "#0B2545"), Color(hex: "#13678A"), Color(hex: "#3BA99C")]
        case .forest: return [Color(hex: "#0F2A1D"), Color(hex: "#2F5D50"), Color(hex: "#6E9E78")]
        case .ember: return [Color(hex: "#2D142C"), Color(hex: "#801336"), Color(hex: "#C96A3A")]
        case .graphite: return [Color(hex: "#111315"), Color(hex: "#2A2E33"), Color(hex: "#4B525A")]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    /// Creates a colour from "#RRGGBB". Falls back to a deep navy if the text is not a colour.
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6, let number = UInt64(text, radix: 16) else {
            self.init(.sRGB, red: 0.086, green: 0.129, blue: 0.227, opacity: 1)
            return
        }
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    /// "#RRGGBB" in sRGB.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

/// A capsule button that draws itself, so it looks the same in panels that never become key.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, prominent: prominent, tint: tint)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let tint: Color

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.white : tint)
            .background(
                Capsule().fill(prominent ? Color.accentColor : tint.opacity(0.1))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
            .contentShape(Capsule())
    }
}

/// The larger outlined button used on the break screen.
struct OverlayButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .foregroundStyle(tint)
            .background(
                Capsule().fill(tint.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Capsule())
    }
}

/// `NSVisualEffectView` for SwiftUI. Used full-bleed on the break screen to blur the desktop.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
