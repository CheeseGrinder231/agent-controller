import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayPanelController {
    private let panel: NonActivatingPanel
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: SessionOverlayView(model: model))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false

        model.$selectorVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                guard let self else { return }
                if visible {
                    self.resizePanel(for: model.selectorSessions.count + model.selectorProjects.count)
                    self.positionPanel()
                    self.panel.orderFrontRegardless()
                } else {
                    self.panel.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$selectorSessions, model.$selectorProjects)
            .map { $0.count + $1.count }
            .removeDuplicates()
            .sink { [weak self] count in
                guard let self, model.selectorVisible else { return }
                self.resizePanel(for: count)
                self.positionPanel()
            }
            .store(in: &cancellables)
    }

    private func resizePanel(for sessionCount: Int) {
        let visibleRows = min(max(sessionCount, 1), 8)
        let height = CGFloat(104 + visibleRows * 57)
        panel.setContentSize(NSSize(width: 600, height: height))
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let x = visibleFrame.midX - panel.frame.width / 2
        let y = visibleFrame.maxY - panel.frame.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
