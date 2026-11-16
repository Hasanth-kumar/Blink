import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case schedule
    case smartPause
    case breakScreen
    case wellness
    case shortcuts
    case stats
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .schedule: return "Break Schedule"
        case .smartPause: return "Smart Pause"
        case .breakScreen: return "Break Screen"
        case .wellness: return "Wellness"
        case .shortcuts: return "Shortcuts"
        case .stats: return "Stats"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .schedule: return "timer"
        case .smartPause: return "sparkles"
        case .breakScreen: return "display"
        case .wellness: return "heart"
        case .shortcuts: return "keyboard"
        case .stats: return "chart.bar"
        case .about: return "info.circle"
        }
    }
}

/// View state for the Settings window.
///
/// This lives in an observable object instead of `@State` on purpose: with the macOS 27 SDK,
/// `@State` is a macro whose compiler plug-in ships only with Xcode, so a build made with the
/// Command Line Tools alone cannot use it. `@Published` and `@EnvironmentObject` work everywhere.
@MainActor
final class SettingsUIState: ObservableObject {
    @Published var selection: SettingsSection? = .general
    @Published var statsRange = 7
    @Published var confirmingStatsReset = false
}

/// The Settings window: a sidebar of sections on the left, the chosen section on the right.
struct SettingsView: View {
    @EnvironmentObject private var ui: SettingsUIState

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $ui.selection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 204)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        switch ui.selection ?? .general {
        case .general: GeneralSettingsView()
        case .schedule: ScheduleSettingsView()
        case .smartPause: SmartPauseSettingsView()
        case .breakScreen: BreakScreenSettingsView()
        case .wellness: WellnessSettingsView()
        case .shortcuts: ShortcutsSettingsView()
        case .stats: StatsView()
        case .about: AboutView()
        }
    }
}

// MARK: - Shared building blocks

/// A titled page of grouped settings.
struct SettingsPage<Content: View>: View {
    private let title: String
    private let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 2)

            Form {
                content()
            }
            .formStyle(.grouped)
        }
    }
}

/// A row with a title on the left and a "20 min ⬍" stepper on the right.
struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let unit: String

    var body: some View {
        LabeledContent(title) {
            Stepper(value: $value, in: range, step: step) {
                Text("\(value) \(unit)")
                    .monospacedDigit()
            }
        }
    }
}

/// Small grey explanatory text under a group of controls.
struct Hint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Hooks the Settings UI uses to reach the rest of the app without knowing about it.
@MainActor
final class AppActions {
    static let shared = AppActions()

    var previewBreakScreen: () -> Void = {}
    var previewNudge: (NudgeKind) -> Void = { _ in }
    var openSettings: () -> Void = {}

    private init() {}
}
