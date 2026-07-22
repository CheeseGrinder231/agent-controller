public struct ControllerReconnectPolicy: Equatable, Sendable {
    private var shouldResumeAfterReconnect = false

    public init() {}

    public mutating func controllerDisconnected(wasEnabled: Bool) {
        shouldResumeAfterReconnect = wasEnabled
    }

    public mutating func userChangedEnablement(_ isEnabled: Bool) {
        if !isEnabled {
            shouldResumeAfterReconnect = false
        }
    }

    public mutating func controllerConnected() -> Bool {
        defer { shouldResumeAfterReconnect = false }
        return shouldResumeAfterReconnect
    }
}
