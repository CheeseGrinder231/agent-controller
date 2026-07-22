import Foundation

public enum SelectionDirection: Equatable, Sendable {
    case up
    case down
}

public enum GestureCancellationReason: String, Equatable, Sendable {
    case disarmed
    case earlyRelease
    case noSelection
    case focusChanged
    case controllerChanged
    case controllerDisconnected
    case userCancelled
    case unsupportedApplication
}

public enum GestureOutput: Equatable, Sendable {
    case none
    case showPreview
    case selectionChanged(Int)
    case commitSelection(String, ApplicationContext)
    case cancelled(GestureCancellationReason)
}

public struct HoldSelectionStateMachine: Sendable {
    public struct Session: Equatable, Sendable {
        public let startedAt: TimeInterval
        public let context: ApplicationContext
        public let controllerIdentifier: String
        public let itemIDs: [String]
        public var selectedIndex: Int?
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case holding(Session)
        case previewing(Session)
    }

    public private(set) var phase: Phase = .idle
    public let holdDuration: TimeInterval

    public init(holdDuration: TimeInterval = 0.25) {
        self.holdDuration = holdDuration
    }

    public var selectedIndex: Int? {
        switch phase {
        case .idle:
            nil
        case .holding(let session), .previewing(let session):
            session.selectedIndex
        }
    }

    public var frozenContext: ApplicationContext? {
        switch phase {
        case .idle:
            nil
        case .holding(let session), .previewing(let session):
            session.context
        }
    }

    public mutating func begin(
        at timestamp: TimeInterval,
        context: ApplicationContext?,
        controllerIdentifier: String,
        itemIDs: [String],
        isArmed: Bool
    ) -> GestureOutput {
        guard isArmed else { return .cancelled(.disarmed) }
        guard let context, ProfileRegistry.supports(context) else {
            return .cancelled(.unsupportedApplication)
        }

        phase = .holding(
            Session(
                startedAt: timestamp,
                context: context,
                controllerIdentifier: controllerIdentifier,
                itemIDs: itemIDs,
                selectedIndex: nil
            )
        )
        return .none
    }

    public mutating func activatePreview(at timestamp: TimeInterval) -> GestureOutput {
        guard case .holding(let session) = phase else { return .none }
        guard timestamp - session.startedAt >= holdDuration else { return .none }
        phase = .previewing(session)
        return .showPreview
    }

    public mutating func move(_ direction: SelectionDirection) -> GestureOutput {
        guard case .previewing(var session) = phase, !session.itemIDs.isEmpty else {
            return .none
        }

        let nextIndex: Int
        if let selectedIndex = session.selectedIndex {
            switch direction {
            case .up:
                nextIndex = (selectedIndex - 1 + session.itemIDs.count) % session.itemIDs.count
            case .down:
                nextIndex = (selectedIndex + 1) % session.itemIDs.count
            }
        } else {
            nextIndex = direction == .down ? 0 : session.itemIDs.count - 1
        }

        session.selectedIndex = nextIndex
        phase = .previewing(session)
        return .selectionChanged(nextIndex)
    }

    public mutating func release(
        currentContext: ApplicationContext?,
        controllerIdentifier: String
    ) -> GestureOutput {
        switch phase {
        case .idle:
            return .none
        case .holding:
            phase = .idle
            return .cancelled(.earlyRelease)
        case .previewing(let session):
            phase = .idle
            guard session.controllerIdentifier == controllerIdentifier else {
                return .cancelled(.controllerChanged)
            }
            guard currentContext == session.context else {
                return .cancelled(.focusChanged)
            }
            guard let selectedIndex = session.selectedIndex,
                  session.itemIDs.indices.contains(selectedIndex) else {
                return .cancelled(.noSelection)
            }
            return .commitSelection(session.itemIDs[selectedIndex], session.context)
        }
    }

    public mutating func cancel(_ reason: GestureCancellationReason) -> GestureOutput {
        guard phase != .idle else { return .none }
        phase = .idle
        return .cancelled(reason)
    }

    public mutating func cancelIfContextChanged(to context: ApplicationContext?) -> GestureOutput {
        guard let frozenContext, context != frozenContext else { return .none }
        return cancel(.focusChanged)
    }
}
