import AgentControllerCore

enum SessionInventoryState: Equatable {
    case idle
    case loading
    case ready(count: Int)
    case unavailable
}

enum CodexSelectorMode: Equatable {
    case sessionPicker
    case projectStarter
}

func gestureCancellationMessage(for reason: GestureCancellationReason) -> String {
    switch reason {
    case .disarmed:
        "Disarmed."
    case .earlyRelease:
        "Cancelled: hold LB a little longer."
    case .noSelection:
        "Cancelled: no session was selected."
    case .focusChanged:
        "Cancelled: the frontmost application changed."
    case .controllerChanged:
        "Cancelled: release came from a different controller."
    case .controllerDisconnected:
        "Cancelled: the controller disconnected."
    case .userCancelled:
        "Cancelled."
    case .unsupportedApplication:
        "Focus Codex before using the session picker."
    }
}

func projectGestureCancellationMessage(for reason: GestureCancellationReason) -> String {
    switch reason {
    case .disarmed:
        "Disarmed."
    case .earlyRelease:
        "Cancelled: hold L3 a little longer."
    case .noSelection:
        "Cancelled: no project was selected."
    case .focusChanged:
        "Cancelled: the frontmost application changed."
    case .controllerChanged:
        "Cancelled: release came from a different controller."
    case .controllerDisconnected:
        "Cancelled: the controller disconnected."
    case .userCancelled:
        "Cancelled."
    case .unsupportedApplication:
        "Focus Codex before using the Session Starter."
    }
}

func dictationCancellationMessage(for reason: VoiceHoldCancellationReason) -> String {
    switch reason {
    case .disarmed:
        "Disarmed."
    case .focusChanged:
        "RB dictation stopped because the frontmost application changed."
    case .controllerChanged:
        "RB dictation stopped because the controller changed."
    case .controllerDisconnected:
        "RB dictation stopped because the controller disconnected."
    case .userCancelled:
        "RB dictation cancelled."
    case .unsupportedApplication:
        "Focus Codex before holding RB to dictate."
    case .adapterBlocked:
        "RB dictation adapter blocked the command."
    }
}
