import Foundation

public enum ControllerInputControl: String, Codable, CaseIterable, Sendable {
    case leftShoulder
    case leftStickButton
    case leftTrigger
    case rightTrigger
    case buttonA
    case rightShoulder
    case buttonX
    case directionalPad
    case leftStick
    case rightStick
    case buttonB
    case buttonY

    public var displayName: String {
        switch self {
        case .leftShoulder: "LB"
        case .leftStickButton: "L3"
        case .leftTrigger: "LT"
        case .rightTrigger: "RT"
        case .buttonA: "A"
        case .rightShoulder: "RB"
        case .buttonX: "X"
        case .directionalPad: "D-pad"
        case .leftStick: "L Stick"
        case .rightStick: "R Stick"
        case .buttonB: "B"
        case .buttonY: "Y"
        }
    }
}

public enum ControllerInputGesture: String, Codable, Sendable {
    case pressed
    case released
    case moved

    public var displayName: String {
        rawValue.capitalized
    }
}

public enum ControllerSemanticAction: String, Codable, CaseIterable, Sendable {
    case sessionPicker = "session_picker"
    case projectStarter = "project_starter"
    case commandModifier = "command_modifier"
    case tab = "tab"
    case enter = "enter"
    case pushToTalk = "push_to_talk"
    case stop = "stop"
    case selectorNavigation = "selector_navigation"
    case sessionScroll = "session_scroll"
    case cancel = "cancel"
    case showController = "show_controller"

    public var displayName: String {
        switch self {
        case .sessionPicker: "Session Picker"
        case .projectStarter: "Session Starter"
        case .commandModifier: "Command Modifier"
        case .tab: "Tab"
        case .enter: "Enter / Submit"
        case .pushToTalk: "Push to Talk"
        case .stop: "Stop"
        case .selectorNavigation: "Navigate Selector"
        case .sessionScroll: "Scroll Session"
        case .cancel: "Cancel"
        case .showController: "Open Agent Controller"
        }
    }
}

public enum InputMonitorStatus: String, Codable, Sendable {
    case observed
    case routed
    case completed
    case blocked
    case cancelled
    case failed

    public var displayName: String {
        rawValue.capitalized
    }
}

public struct InputMonitorEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var occurredAt: Date
    public let input: ControllerInputControl
    public let gesture: ControllerInputGesture
    public let action: ControllerSemanticAction
    public let route: String
    public let applicationName: String
    public var status: InputMonitorStatus
    public var detail: String

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        input: ControllerInputControl,
        gesture: ControllerInputGesture,
        action: ControllerSemanticAction,
        route: String,
        applicationName: String,
        status: InputMonitorStatus = .observed,
        detail: String = "Input observed."
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.input = input
        self.gesture = gesture
        self.action = action
        self.route = route
        self.applicationName = applicationName
        self.status = status
        self.detail = detail
    }
}

public struct InputMonitorBuffer: Equatable, Sendable {
    public private(set) var events: [InputMonitorEvent] = []
    public let capacity: Int

    public init(capacity: Int = 24) {
        self.capacity = max(capacity, 1)
    }

    @discardableResult
    public mutating func begin(
        input: ControllerInputControl,
        gesture: ControllerInputGesture,
        action: ControllerSemanticAction,
        route: String,
        applicationName: String,
        occurredAt: Date = Date()
    ) -> UUID {
        let event = InputMonitorEvent(
            occurredAt: occurredAt,
            input: input,
            gesture: gesture,
            action: action,
            route: route,
            applicationName: applicationName
        )
        events.insert(event, at: 0)
        if events.count > capacity {
            events.removeLast(events.count - capacity)
        }
        return event.id
    }

    public mutating func finish(
        _ id: UUID,
        status: InputMonitorStatus,
        detail: String,
        occurredAt: Date = Date()
    ) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].occurredAt = occurredAt
        events[index].status = status
        events[index].detail = detail
    }

    public mutating func clear() {
        events.removeAll(keepingCapacity: true)
    }
}
