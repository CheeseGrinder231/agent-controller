import AgentControllerCore
import Foundation

extension AppModel {
    @discardableResult
    func beginInputMonitorEvent(
        input: ControllerInputControl,
        gesture: ControllerInputGesture,
        action: ControllerSemanticAction,
        route: String
    ) -> UUID {
        let id = inputMonitorBuffer.begin(
            input: input,
            gesture: gesture,
            action: action,
            route: route,
            applicationName: context?.displayName ?? "System"
        )
        inputMonitorEvents = inputMonitorBuffer.events
        return id
    }

    func finishInputMonitorEvent(
        _ id: UUID?,
        status: InputMonitorStatus,
        detail: String
    ) {
        guard let id else { return }
        inputMonitorBuffer.finish(id, status: status, detail: detail)
        inputMonitorEvents = inputMonitorBuffer.events
    }

    func clearInputMonitor() {
        inputMonitorBuffer.clear()
        inputMonitorEvents = inputMonitorBuffer.events
    }
}
