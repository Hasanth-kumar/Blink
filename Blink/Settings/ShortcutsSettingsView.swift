import SwiftUI
import AppKit

struct ShortcutsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsPage(title: "Shortcuts") {
            Section("Global keyboard shortcuts") {
                ForEach(HotKeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 6) {
                            ShortcutRecorder(hotKey: binding(for: action))
                                .frame(width: 160, height: 24)
                            Button {
                                settings.setHotKey(nil, for: action)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Clear shortcut")
                            .opacity(settings.hotKey(for: action) == nil ? 0 : 1)
                            .disabled(settings.hotKey(for: action) == nil)
                        }
                    }
                }
                Hint("Click a field, then press the keys. Shortcuts need ⌘, ⌥ or ⌃ (function keys work on their own). Press Esc to cancel or ⌫ to clear.")
            }

            Section {
                Hint("These work in every app. If a shortcut does nothing, another app is probably already using that combination.")
            }
        }
    }

    private func binding(for action: HotKeyAction) -> Binding<HotKey?> {
        Binding(
            get: { settings.hotKey(for: action) },
            set: { settings.setHotKey($0, for: action) }
        )
    }
}

/// A button that records the next key combination pressed.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotKey: HotKey?

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(frame: .zero)
        button.hotKey = hotKey
        button.onChange = { newValue in
            hotKey = newValue
        }
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        if nsView.hotKey != hotKey {
            nsView.hotKey = hotKey
        }
        nsView.onChange = { newValue in
            hotKey = newValue
        }
    }
}
