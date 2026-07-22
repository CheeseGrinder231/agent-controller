public enum ControllerCommandIntent: Equatable, Sendable {
    case sessionPicker
    case projectStarter
    case dictation
    case stop
    case commandModifier
    case tabPulse
    case enterPulse
    case sessionScroll
    case showConsole
}

public struct ControllerCommandActivity: Equatable, Sendable {
    public let appLocalCommandActive: Bool
    public let commandModifierHeld: Bool
    public let releasePending: Bool
    public let recordingBinding: Bool

    public init(
        appLocalCommandActive: Bool,
        commandModifierHeld: Bool,
        releasePending: Bool,
        recordingBinding: Bool = false
    ) {
        self.appLocalCommandActive = appLocalCommandActive
        self.commandModifierHeld = commandModifierHeld
        self.releasePending = releasePending
        self.recordingBinding = recordingBinding
    }
}

public enum ControllerCommandArbiter {
    public static func allows(
        _ intent: ControllerCommandIntent,
        activity: ControllerCommandActivity
    ) -> Bool {
        guard !activity.releasePending, !activity.recordingBinding else { return false }
        if activity.commandModifierHeld {
            return intent == .tabPulse || intent == .enterPulse
        }
        guard !activity.appLocalCommandActive else { return false }
        return true
    }
}
