import SwiftUI

struct WellnessSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    private var blinkScript: NudgeScript {
        NudgeScript(kind: .blink, blinkStyle: settings.blinkStyle, postureStyle: settings.postureStyle)
    }

    private var postureScript: NudgeScript {
        NudgeScript(kind: .posture, blinkStyle: settings.blinkStyle, postureStyle: settings.postureStyle)
    }

    var body: some View {
        SettingsPage(title: "Wellness") {
            Section("Blink reminders") {
                Toggle("Remind me to blink", isOn: $settings.blinkEnabled)
                if settings.blinkEnabled {
                    StepperRow(title: "Every", value: $settings.blinkMinutes, range: 1...60, unit: "min")
                }
                Picker("Animation", selection: $settings.blinkStyle) {
                    ForEach(BlinkNudgeStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                NudgePreview(script: blinkScript)
                Toggle("Play a sound", isOn: $settings.blinkSoundEnabled)
                Button("Show Me") {
                    AppActions.shared.previewNudge(.blink)
                }
                Hint("People blink far less while looking at a screen. A small animation plays for a few seconds. It never takes focus and never blocks a click.")
            }

            Section("Posture reminders") {
                Toggle("Remind me to check my posture", isOn: $settings.postureEnabled)
                if settings.postureEnabled {
                    StepperRow(title: "Every", value: $settings.postureMinutes, range: 5...120, step: 5, unit: "min")
                }
                Picker("Animation", selection: $settings.postureStyle) {
                    ForEach(PostureNudgeStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                NudgePreview(script: postureScript)
                Toggle("Play a sound", isOn: $settings.postureSoundEnabled)
                Button("Show Me") {
                    AppActions.shared.previewNudge(.posture)
                }
            }

            Section("Look and sound") {
                Picker("Size", selection: $settings.nudgeSize) {
                    ForEach(NudgeSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                Picker("Position", selection: $settings.nudgePosition) {
                    ForEach(NudgePosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                Toggle("Dim the screen slightly while a reminder plays", isOn: $settings.nudgeDimsScreen)
                Toggle("Show a short caption under the animation", isOn: $settings.nudgeShowsCaption)
                Slider(value: $settings.nudgeVolume, in: 0...1) {
                    Text("Sound volume")
                }
                Hint("The volume applies to both reminders. Each one's sound can be turned off on its own above.")
            }

            Section {
                Hint("Nudges only appear while the work timer is running. They stay out of the way during breaks, calls, full-screen video and when a break is about to start.")
            }
        }
    }
}
