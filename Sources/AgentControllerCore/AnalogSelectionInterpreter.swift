import Foundation

public struct AnalogSelectionInterpreter: Sendable {
    public let entryThreshold: Float
    public let neutralThreshold: Float
    public let verticalDominanceMargin: Float
    public let initialRepeatDelay: TimeInterval
    public let repeatInterval: TimeInterval

    public private(set) var isActive = false
    public private(set) var activeDirection: SelectionDirection?

    private var isArmedForEntry = false
    private var nextRepeatAt: TimeInterval?

    public init(
        entryThreshold: Float = 0.70,
        neutralThreshold: Float = 0.35,
        verticalDominanceMargin: Float = 0.15,
        initialRepeatDelay: TimeInterval = 0.40,
        repeatInterval: TimeInterval = 0.16
    ) {
        self.entryThreshold = entryThreshold
        self.neutralThreshold = neutralThreshold
        self.verticalDominanceMargin = verticalDominanceMargin
        self.initialRepeatDelay = initialRepeatDelay
        self.repeatInterval = repeatInterval
    }

    public mutating func activate(currentX: Float, currentY: Float) {
        isActive = true
        activeDirection = nil
        nextRepeatAt = nil
        isArmedForEntry = isNeutral(x: currentX, y: currentY)
    }

    public mutating func deactivate() {
        isActive = false
        isArmedForEntry = false
        activeDirection = nil
        nextRepeatAt = nil
    }

    public mutating func update(
        x: Float,
        y: Float,
        at timestamp: TimeInterval
    ) -> SelectionDirection? {
        guard isActive else { return nil }
        if isNeutral(x: x, y: y) {
            isArmedForEntry = true
            activeDirection = nil
            nextRepeatAt = nil
            return nil
        }

        guard let candidate = direction(x: x, y: y) else {
            activeDirection = nil
            nextRepeatAt = nil
            return nil
        }
        guard isArmedForEntry else {
            if candidate != activeDirection {
                activeDirection = nil
                nextRepeatAt = nil
            }
            return nil
        }

        isArmedForEntry = false
        activeDirection = candidate
        nextRepeatAt = timestamp + initialRepeatDelay
        return candidate
    }

    public mutating func repeatedMove(at timestamp: TimeInterval) -> SelectionDirection? {
        guard isActive,
              let activeDirection,
              let nextRepeatAt,
              timestamp >= nextRepeatAt else { return nil }
        self.nextRepeatAt = timestamp + repeatInterval
        return activeDirection
    }

    public mutating func dpadDidMove(currentX: Float, currentY: Float) {
        guard isActive else { return }
        activeDirection = nil
        nextRepeatAt = nil
        isArmedForEntry = isNeutral(x: currentX, y: currentY)
    }

    private func isNeutral(x: Float, y: Float) -> Bool {
        abs(x) <= neutralThreshold && abs(y) <= neutralThreshold
    }

    private func direction(x: Float, y: Float) -> SelectionDirection? {
        guard abs(y) >= entryThreshold,
              abs(y) >= abs(x) + verticalDominanceMargin else { return nil }
        return y > 0 ? .up : .down
    }
}
