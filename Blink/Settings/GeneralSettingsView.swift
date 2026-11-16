import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var launchAtLogin: LaunchAtLogin
    @EnvironmentObject private var scheduler: BreakScheduler

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    var body: some View {
        SettingsPage(title: "General") {
            Section("Right now") {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    LabeledContent("Status") {
                        Text(scheduler.statusText())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Take a Break Now") {
                        scheduler.startBreakNow()
                    }
                    .disabled(scheduler.isOnBreak)

                    Button(scheduler.isPaused ? "Resume" : "Pause") {
                        scheduler.togglePause()
                    }
                    .disabled(scheduler.isOnBreak)
                }
            }

            Section("Startup") {
                Toggle("Open Blink at login", isOn: loginBinding)
                if launchAtLogin.needsApproval {
                    Hint("Blink is waiting for approval. Allow it in System Settings → General → Login Items.")
                }
                if let error = launchAtLogin.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Menu bar and Dock") {
                Picker("Menu bar shows", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle("Show Blink in the Dock", isOn: $settings.showInDock)
            }

            Section("Focus") {
                Hint("Blink can pause itself while a Focus is on. Open System Settings → Focus, pick a Focus, then choose Focus Filters → Add Filter → Blink and turn on “Pause break reminders”.")
            }

            Section("Automation") {
                Hint("Other apps and scripts can control Blink with links: blink://break, blink://pause?minutes=30, blink://resume and blink://skip. The same actions are available in the Shortcuts app.")
            }
        }
    }
}
