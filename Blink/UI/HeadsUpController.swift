import AppKit
import SwiftUI
import Combine

/// Shows and hides the pre-break heads-up as the scheduler moves through its states.
@MainActor
final class HeadsUpController {
    private let scheduler: BreakScheduler
    private let settings: AppSettings
    private let model = HeadsUpModel()
    private var panel: PassivePanel?
    private var cancellables = Set<AnyCancellable>()
    private var isVisible = false
    private var generation = 0

    init(scheduler: BreakScheduler, settings: AppSettings) {
        self.scheduler = scheduler
        self.settings = settings

        model.onStartNow = { [weak scheduler] in
            scheduler?.startBreakNow()
        }
        model.onSnooze = { [weak scheduler] minutes in
            scheduler?.snooze(minutes: minutes)
        }
        model.onSkip = { [weak scheduler] in
            scheduler?.skip()
        }

        scheduler.didUpdate
            .sink { [weak self] _ in
                self?.sync()
            }
            .store(in: &cancellables)
    }

    private func sync() {
        switch scheduler.state {
        case .preBreakWarning(let breakAt):
            update(breakAt: breakAt, waitingForTyping: false)
            show()
        case .holding(let reason, _):
            // Keep the card up while the break waits for a pause in typing, so the
            // user can see why nothing happened. Other holds (a call, a video) hide it.
            if reason == .typing, isVisible {
                update(breakAt: Date(), waitingForTyping: true)
            } else {
                hide()
            }
        case .working, .onBreak, .paused, .idle, .outsideOfficeHours:
            hide()
        }
    }

    private func update(breakAt: Date, waitingForTyping: Bool) {
        let kind = scheduler.nextBreakKind
        let duration = scheduler.breakDuration(kind)
        let snoozesLeft = scheduler.snoozesRemaining

        // Assign only real changes: every assignment re-renders the card.
        if model.isWaitingForTyping != waitingForTyping { model.isWaitingForTyping = waitingForTyping }
        if !waitingForTyping, model.breakAt != breakAt { model.breakAt = breakAt }
        if model.warningLength != scheduler.warningLength { model.warningLength = scheduler.warningLength }
        if model.kind != kind { model.kind = kind }
        if model.breakDuration != duration { model.breakDuration = duration }
        if model.snoozesLeft != snoozesLeft { model.snoozesLeft = snoozesLeft }
        if model.showSnoozesLeft != settings.showSnoozesLeft { model.showSnoozesLeft = settings.showSnoozesLeft }
        if model.canSnooze != scheduler.canSnooze { model.canSnooze = scheduler.canSnooze }
        if model.canSkip != scheduler.canSkip { model.canSkip = scheduler.canSkip }
        if model.compact != settings.warningCompact { model.compact = settings.warningCompact }
    }

    private func show() {
        guard !isVisible else { return }
        isVisible = true
        generation += 1
        if model.isHovering { model.isHovering = false }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.isReduced ? 0.01 : 0.25
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard isVisible, let panel = panel else { return }
        isVisible = false
        generation += 1
        let token = generation
        let duration = Motion.isReduced ? 0.01 : 0.2

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.05) * 1_000_000_000))
            // Only take the panel down if nothing asked for it again in the meantime.
            guard let self = self, self.generation == token else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> PassivePanel {
        let size = HeadsUpView.panelSize
        let panel = PassivePanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.configureAsOverlay(level: .statusBar)
        panel.contentView = FirstClickHostingView(rootView: HeadsUpView(model: model))
        return panel
    }

    /// Top-right corner of the display the pointer is on, just under the menu bar.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.withPointer else { return }
        let visible = screen.visibleFrame
        let size = HeadsUpView.panelSize
        let origin = NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
