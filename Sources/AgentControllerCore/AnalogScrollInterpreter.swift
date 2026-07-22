import Foundation

public struct AnalogScrollConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var inverted: Bool
    public var speed: Double

    public init(enabled: Bool = true, inverted: Bool = false, speed: Double = 0.55) {
        self.enabled = enabled
        self.inverted = inverted
        self.speed = min(max(speed, 0), 1)
    }

    public static let `default` = AnalogScrollConfiguration()
}

public struct AnalogScrollInterpreter: Sendable {
    public let deadZone: Float
    public let verticalIntentRatio: Float
    public let minimumPointsPerSecond: Double
    public let maximumPointsPerSecond: Double

    public private(set) var isActive = false
    public private(set) var ratePointsPerSecond: Double = 0

    private var requiresNeutral = true
    private var fractionalDelta = 0.0

    public init(
        deadZone: Float = 0.20,
        verticalIntentRatio: Float = 1.25,
        minimumPointsPerSecond: Double = 120,
        maximumPointsPerSecond: Double = 1_200
    ) {
        self.deadZone = deadZone
        self.verticalIntentRatio = verticalIntentRatio
        self.minimumPointsPerSecond = minimumPointsPerSecond
        self.maximumPointsPerSecond = maximumPointsPerSecond
    }

    public mutating func activate(currentX: Float, currentY: Float) {
        isActive = true
        ratePointsPerSecond = 0
        fractionalDelta = 0
        requiresNeutral = !isNeutral(x: currentX, y: currentY)
    }

    public mutating func deactivate() {
        isActive = false
        ratePointsPerSecond = 0
        fractionalDelta = 0
        requiresNeutral = true
    }

    public mutating func update(
        x: Float,
        y: Float,
        configuration: AnalogScrollConfiguration
    ) {
        guard isActive, configuration.enabled else {
            ratePointsPerSecond = 0
            fractionalDelta = 0
            return
        }
        if isNeutral(x: x, y: y) {
            requiresNeutral = false
            ratePointsPerSecond = 0
            fractionalDelta = 0
            return
        }
        guard !requiresNeutral,
              abs(y) >= deadZone,
              abs(y) >= verticalIntentRatio * abs(x) else {
            ratePointsPerSecond = 0
            fractionalDelta = 0
            return
        }

        let normalized = Double(min(max((abs(y) - deadZone) / (1 - deadZone), 0), 1))
        let maximum = minimumPointsPerSecond
            + (maximumPointsPerSecond - minimumPointsPerSecond) * configuration.speed
        let magnitude = minimumPointsPerSecond + (maximum - minimumPointsPerSecond) * normalized * normalized
        let direction = (y > 0 ? 1.0 : -1.0) * (configuration.inverted ? -1.0 : 1.0)
        ratePointsPerSecond = magnitude * direction
    }

    public mutating func delta(elapsed: TimeInterval) -> Int32 {
        guard isActive, ratePointsPerSecond != 0, elapsed > 0 else { return 0 }
        let total = ratePointsPerSecond * elapsed + fractionalDelta
        let integral = total.rounded(.towardZero)
        fractionalDelta = total - integral
        return Int32(clamping: Int(integral))
    }

    private func isNeutral(x: Float, y: Float) -> Bool {
        abs(x) < deadZone && abs(y) < deadZone
    }
}
