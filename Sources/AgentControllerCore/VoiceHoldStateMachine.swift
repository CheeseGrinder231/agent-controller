public enum VoiceHoldCancellationReason: String, Equatable, Sendable {
    case disarmed
    case focusChanged
    case controllerChanged
    case controllerDisconnected
    case userCancelled
    case unsupportedApplication
    case adapterBlocked
}

public enum VoiceHoldOutput: Equatable, Sendable {
    case none
    case beginDictation(ApplicationContext)
    case endDictation
    case cancelled(VoiceHoldCancellationReason, shouldEndDictation: Bool)
}

public struct VoiceHoldStateMachine: Sendable {
    public struct Hold: Equatable, Sendable {
        public let context: ApplicationContext
        public let controllerIdentifier: String
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case holding(Hold)
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    public mutating func begin(
        context: ApplicationContext?,
        controllerIdentifier: String,
        isArmed: Bool
    ) -> VoiceHoldOutput {
        guard phase == .idle else { return .none }
        guard isArmed else {
            return .cancelled(.disarmed, shouldEndDictation: false)
        }
        guard let context, ProfileRegistry.supports(context) else {
            return .cancelled(.unsupportedApplication, shouldEndDictation: false)
        }

        phase = .holding(Hold(context: context, controllerIdentifier: controllerIdentifier))
        return .beginDictation(context)
    }

    public mutating func release(
        currentContext: ApplicationContext?,
        controllerIdentifier: String
    ) -> VoiceHoldOutput {
        guard case .holding(let hold) = phase else { return .none }
        phase = .idle

        guard hold.controllerIdentifier == controllerIdentifier else {
            return .cancelled(.controllerChanged, shouldEndDictation: true)
        }
        guard currentContext == hold.context else {
            return .cancelled(.focusChanged, shouldEndDictation: true)
        }
        return .endDictation
    }

    public mutating func cancel(_ reason: VoiceHoldCancellationReason) -> VoiceHoldOutput {
        guard phase != .idle else { return .none }
        phase = .idle
        return .cancelled(reason, shouldEndDictation: true)
    }

    public mutating func cancelIfContextChanged(
        to context: ApplicationContext?
    ) -> VoiceHoldOutput {
        guard case .holding(let hold) = phase, context != hold.context else { return .none }
        return cancel(.focusChanged)
    }
}
