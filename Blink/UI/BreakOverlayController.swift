import AppKit
import SwiftUI
import Combine

/// Covers every display with the break screen while the scheduler is on a break.
@MainActor
final class BreakOverlayController: NSObject {
    private let scheduler: BreakScheduler
    private let settings: AppSettings
    private let model = BreakOverlayModel()
    private var panels: [NSPanel] = []
    private var cancellables = Set<AnyCancellable>()
    private var isShowing = false
    private var previewToken = 0

    init(scheduler: BreakScheduler, settings: AppSettings) {
        self.scheduler = scheduler
        self.settings = settings
        super.init()

        model.onSkip = { [weak self] in
            self?.skipPressed()
        }

        scheduler.didUpdate
            .sink { [weak self] _ in
                self?.sync()
            }
            .store(in: &cancellables)

        // Displays can be plugged in or removed in the middle of a break.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        sync()
    }

    // MARK: Following the scheduler

    private func sync() {
        if case .onBreak(let kind, let startedAt, let endsAt) = scheduler.state {
            if model.isPreview { model.isPreview = false }
            if model.kind != kind { model.kind = kind }
            if model.startedAt != startedAt { model.startedAt = startedAt }
            if model.endsAt != endsAt { model.endsAt = endsAt }
            if model.message != scheduler.currentMessage { model.message = scheduler.currentMessage }
            if model.allowSkip != scheduler.canSkip { model.allowSkip = scheduler.canSkip }
            present()
        } else if isShowing, !model.isPreview {
            dismiss()
        }
    }

    /// Shows the break screen for a few seconds without affecting the schedule.
    func showPreview() {
        guard !scheduler.isOnBreak else { return }
        let now = Date()
        model.isPreview = true
        model.kind = .short
        model.startedAt = now
        model.endsAt = now.addingTimeInterval(10)
        model.message = settings.messages(for: .short).first ?? ""
        model.allowSkip = true
        present()

        previewToken += 1
        let token = previewToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self = self, self.previewToken == token, self.model.isPreview else { return }
            self.dismiss()
        }
    }

    private func skipPressed() {
        if model.isPreview {
            dismiss()
        } else {
            scheduler.skip()
        }
    }

    // MARK: Windows

    private var fadeDuration: TimeInterval {
        Motion.isReduced ? 0.12 : 0.6
    }

    private func present() {
        guard !isShowing else { return }
        isShowing = true
        loadBackgroundImage()
        buildPanels(animated: true)
    }

    private func dismiss() {
        guard isShowing else { return }
        isShowing = false
        if model.isPreview { model.isPreview = false }

        let closing = panels
        panels = []
        let duration = fadeDuration * 0.7

        for panel in closing {
            // Let clicks through straight away; the fade is only cosmetic.
            panel.ignoresMouseEvents = true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            for panel in closing {
                panel.animator().alphaValue = 0
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.05) * 1_000_000_000))
            for panel in closing {
                panel.orderOut(nil)
            }
        }
    }

    private func buildPanels(animated: Bool) {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels = []

        let screens = NSScreen.screens
        let primary = NSScreen.withPointer ?? screens.first
        var keyPanel: NSPanel?

        for screen in screens {
            let panel = KeyablePanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.configureAsOverlay(level: .screenSaver)
            panel.setFrame(screen.frame, display: false)
            panel.contentView = NSHostingView(
                rootView: BreakOverlayView(model: model).environmentObject(settings)
            )
            panel.alphaValue = animated ? 0 : 1
            panel.orderFrontRegardless()
            panels.append(panel)
            if screen == primary {
                keyPanel = panel
            }
        }

        // Take the keyboard (without activating Blink) so Esc reaches the Skip button
        // and stray typing does not land in the app underneath.
        let panelForKeys = keyPanel ?? panels.first
        panelForKeys?.makeKey()

        if animated {
            let opening = panels
            let duration = fadeDuration
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                for panel in opening {
                    panel.animator().alphaValue = 1
                }
            }
        }
    }

    private func loadBackgroundImage() {
        guard settings.backgroundStyle == .image, !settings.customImagePath.isEmpty else {
            model.backgroundImage = nil
            return
        }
        model.backgroundImage = NSImage(contentsOfFile: settings.customImagePath)
    }

    @objc private func screensDidChange(_ notification: Notification) {
        guard isShowing else { return }
        buildPanels(animated: false)
    }
}
