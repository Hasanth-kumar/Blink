import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SmartPauseSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsPage(title: "Smart Pause") {
            Section("When you step away") {
                Toggle("Restart the timer after I've been away", isOn: $settings.idleResetEnabled)
                if settings.idleResetEnabled {
                    StepperRow(title: "Count me as away after", value: $settings.idleMinutes, range: 1...30, unit: "min")
                }
                Hint("Time away from the keyboard is a break already, so Blink starts a fresh countdown when you return. Locking the screen or closing the lid counts too.")
            }

            Section("Hold breaks during") {
                Toggle("Calls (camera or microphone in use)", isOn: $settings.pauseDuringCalls)
                Toggle("Full-screen video", isOn: $settings.pauseDuringFullscreenVideo)
                Toggle("Screen recording", isOn: $settings.pauseDuringScreenRecording)
                Toggle("Presentations (Keynote, PowerPoint)", isOn: $settings.pauseDuringPresentations)
                Toggle("Full-screen games", isOn: $settings.pauseDuringGames)
                Hint("The break waits until the activity ends, then gives you a short heads-up first.")
            }

            Section("Typing") {
                Toggle("Wait for a pause in typing", isOn: $settings.deferWhileTyping)
                if settings.deferWhileTyping {
                    StepperRow(title: "Start after", value: $settings.typingQuietSeconds, range: 1...10, unit: "sec without a key press")
                }
                Hint("Blink never interrupts mid-sentence. If you keep typing for a full minute, the break starts anyway.")
            }

            Section("Never interrupt these apps") {
                if settings.excludedApps.isEmpty {
                    Text("No apps added.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.excludedApps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        Button {
                            remove(app)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(app.name)")
                    }
                }
                Button("Add App…") {
                    addApps()
                }
                Hint("Breaks are held while one of these apps is in front.")
            }
        }
    }

    private func remove(_ app: ExcludedApp) {
        settings.excludedApps.removeAll { $0.bundleID == app.bundleID }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }

        var apps = settings.excludedApps
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            if apps.contains(where: { $0.bundleID == bundleID }) { continue }
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") {
                name = String(name.dropLast(4))
            }
            apps.append(ExcludedApp(bundleID: bundleID, name: name, path: url.path))
        }
        settings.excludedApps = apps
    }
}
