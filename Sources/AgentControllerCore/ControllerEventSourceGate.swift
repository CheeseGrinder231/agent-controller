public struct ControllerEventSourceGate: Equatable, Sendable {
    public private(set) var activeControllerIdentifier: String?

    public init() {}

    public mutating func activate(_ controllerIdentifier: String) {
        activeControllerIdentifier = controllerIdentifier
    }

    public mutating func deactivate() {
        activeControllerIdentifier = nil
    }

    public func allows(_ controllerIdentifier: String) -> Bool {
        activeControllerIdentifier == controllerIdentifier
    }
}
