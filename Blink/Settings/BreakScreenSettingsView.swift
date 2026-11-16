import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BreakScreenSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    private var solidColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.solidColorHex) },
            set: { settings.solidColorHex = $0.hexString }
        )
    }

    var body: some View {
        SettingsPage(title: "Break Screen") {
            Section("Appearance") {
                Picker("Background", selection: $settings.backgroundStyle) {
                    ForEach(BreakBackground.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                backgroundOptions
                Button("Preview Break Screen") {
                    AppActions.shared.previewBreakScreen()
                }
            }

            MessageListEditor(
                title: "Messages for eye breaks",
                messages: $settings.shortMessages,
                defaults: AppSettings.defaultShortMessages
            )

            MessageListEditor(
                title: "Messages for long breaks",
                messages: $settings.longMessages,
                defaults: AppSettings.defaultLongMessages
            )

            Section("Strict mode") {
                Toggle("Hide the Skip button", isOn: $settings.strictMode)
                Hint("In strict mode a break cannot be skipped from the break screen, the heads-up, the menu or a shortcut. Snoozing still follows your snooze limit.")
            }

            Section("Sound") {
                Toggle("Play a chime when the break ends", isOn: $settings.soundEnabled)
                if settings.soundEnabled {
                    Picker("Chime", selection: $settings.soundName) {
                        ForEach(SoundPlayer.availableSounds, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Slider(value: $settings.soundVolume, in: 0...1) {
                        Text("Volume")
                    }
                    Button("Play Chime") {
                        SoundPlayer.play(name: settings.soundName, volume: settings.soundVolume)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var backgroundOptions: some View {
        switch settings.backgroundStyle {
        case .blur:
            Hint("Blurs whatever is on screen and follows light and dark mode.")
        case .solid:
            ColorPicker("Colour", selection: solidColorBinding, supportsOpacity: false)
        case .gradient:
            Picker("Gradient", selection: $settings.gradientPreset) {
                ForEach(GradientPreset.allCases) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
            }
            selectedGradient.gradient
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .image:
            LabeledContent("Image") {
                HStack {
                    Text(imageName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") {
                        chooseImage()
                    }
                }
            }
        }
    }

    private var selectedGradient: GradientPreset {
        GradientPreset(rawValue: settings.gradientPreset) ?? .dusk
    }

    private var imageName: String {
        settings.customImagePath.isEmpty
            ? "None chosen"
            : URL(fileURLWithPath: settings.customImagePath).lastPathComponent
    }

    /// Copies the chosen picture into Application Support so it keeps working
    /// even if the original is moved or deleted.
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let source = panel.url else { return }

        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base
            .appendingPathComponent("Blink", isDirectory: true)
            .appendingPathComponent("Backgrounds", isDirectory: true)
        let destination = folder.appendingPathComponent("background-\(Int(Date().timeIntervalSince1970)).\(source.pathExtension)")

        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            settings.customImagePath = destination.path
        } catch {
            // Fall back to using the picture where it is.
            settings.customImagePath = source.path
        }
    }
}

/// An editable list of break messages.
struct MessageListEditor: View {
    let title: String
    @Binding var messages: [String]
    let defaults: [String]

    var body: some View {
        Section {
            ForEach(messages.indices, id: \.self) { index in
                HStack {
                    TextField("Message", text: binding(for: index))
                        .labelsHidden()
                    Button {
                        remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this message")
                }
            }
            HStack {
                Button("Add Message") {
                    messages.append("")
                }
                Spacer()
                Button("Restore Defaults") {
                    messages = defaults
                }
            }
        } header: {
            Text(title)
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < messages.count ? messages[index] : "" },
            set: { newValue in
                if index < messages.count {
                    messages[index] = newValue
                }
            }
        )
    }

    private func remove(at index: Int) {
        guard index < messages.count else { return }
        messages.remove(at: index)
    }
}
