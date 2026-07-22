import AgentControllerCore

extension AppModel {
    func handleControllerConnectionChange(_ name: String?) {
        guard let name else {
            publishEvent("No controller connected. Pair one in System Settings.")
            return
        }

        if reconnectPolicy.controllerConnected() {
            isArmed = true
            publishEvent("\(name) reconnected. Controller enabled automatically.")
        } else {
            publishEvent(
                "\(name) connected. Controller commands remain \(isArmed ? "enabled" : "paused")."
            )
        }
    }

    func handleActiveControllerDisconnect() {
        reconnectPolicy.controllerDisconnected(wasEnabled: isArmed)
        stopTask?.cancel()
        cancelMappingRecording()
        cancelGesture(.controllerDisconnected)
        cancelVoice(.controllerDisconnected)
        _ = endGlobalCommand(maxAttempts: 5)
        let releasePending = hasPendingKeyRelease
        publishEvent(
            releasePending
                ? "Controller disconnected. A key release is still pending; press B to retry."
                : "Controller disconnected. Active commands were cancelled.",
            safetyCritical: releasePending
        )
    }
}
