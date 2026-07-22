import AgentControllerCore
import AgentControllerMac
import Foundation

extension AppModel {
    func setScrollEnabled(_ enabled: Bool) {
        mappingSettings.codexScroll.enabled = enabled
        persistScrollSettings()
    }

    func setScrollInverted(_ inverted: Bool) {
        mappingSettings.codexScroll.inverted = inverted
        persistScrollSettings()
    }

    func setScrollSpeed(_ speed: Double) {
        mappingSettings.codexScroll.speed = min(max(speed, 0), 1)
        persistScrollSettings()
    }

    func resetScrollSettings() {
        mappingSettings.codexScroll = .default
        persistScrollSettings()
    }

    func handleSessionScroll(delta: Int32, monitorEventID: UUID? = nil) {
        guard isArmed,
              mappingSettings.codexScroll.enabled,
              allows(.sessionScroll),
              let frozenContext = context,
              isCodexFrontmost else {
            controllerMonitor.setSessionScrollingActive(
                false,
                configuration: mappingSettings.codexScroll
            )
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: scrollBlockedMonitorDetail)
            return
        }
        do {
            try scrollAdapter.scroll(delta: delta, frozenContext: frozenContext)
            accessibilityAuthorized = true
            finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Scroll event posted.")
        } catch {
            controllerMonitor.setSessionScrollingActive(
                false,
                configuration: mappingSettings.codexScroll
            )
            publishScrollFailure(error)
            finishInputMonitorEvent(monitorEventID, status: .failed, detail: "Scroll adapter stopped.")
        }
    }

    func synchronizeScrollAvailability() {
        let isAvailable = isArmed
            && isCodexFrontmost
            && mappingSettings.codexScroll.enabled
            && allows(.sessionScroll)
        controllerMonitor.setSessionScrollingActive(
            isAvailable,
            configuration: mappingSettings.codexScroll
        )
    }

    private func publishScrollFailure(_ error: Error) {
        switch error as? CodexScrollError {
        case .accessibilityPermissionRequired:
            accessibilityAuthorized = false
            publishEvent("Session scrolling needs Accessibility permission.", safetyCritical: true)
        case .windowUnavailable:
            publishEvent("Session scrolling stopped because no usable Codex window was found.")
        case .eventCreationFailed:
            publishEvent("Session scrolling could not create a macOS wheel event.")
        default:
            publishEvent("Session scrolling stopped because Codex focus changed.")
        }
    }

    private var scrollBlockedMonitorDetail: String {
        if !isArmed { return "Controller paused." }
        if !mappingSettings.codexScroll.enabled { return "Session scrolling disabled." }
        if !isCodexFrontmost { return "Codex is not frontmost." }
        return "Another controller command is active."
    }

    private func persistScrollSettings() {
        mappingStore.save(mappingSettings)
        synchronizeScrollAvailability()
    }
}
