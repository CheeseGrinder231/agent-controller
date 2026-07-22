public struct SessionCommitGate: Sendable {
    public private(set) var generation: UInt64 = 0

    public init() {}

    public mutating func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    public mutating func invalidate() {
        generation &+= 1
    }

    public func isCurrent(_ token: UInt64) -> Bool {
        token == generation
    }
}
