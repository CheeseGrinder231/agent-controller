import ApplicationServices
import Foundation

public enum MacCommandTabEvent: Equatable, Sendable {
    case commandDown
    case tabDown(commandHeld: Bool)
    case tabUp(commandHeld: Bool)
    case commandUp
}

public enum MacCommandTabError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case releasePending
    case eventPostFailed
}

@MainActor
public final class MacCommandTabAdapter {
    public private(set) var isHoldingCommand = false
    public private(set) var isHoldingTab = false
    public var releasePending: Bool { isHoldingTab || commandReleasePending }

    private let trustCheck: () -> Bool
    private let permissionRequest: () -> Bool
    private let postEvent: (MacCommandTabEvent) -> Bool
    private var commandReleasePending = false

    public convenience init() {
        self.init(
            trustCheck: { AXIsProcessTrusted() },
            permissionRequest: {
                AXIsProcessTrustedWithOptions(
                    ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                )
            },
            postEvent: Self.postSystemEvent
        )
    }

    public init(
        trustCheck: @escaping () -> Bool,
        permissionRequest: @escaping () -> Bool,
        postEvent: @escaping (MacCommandTabEvent) -> Bool
    ) {
        self.trustCheck = trustCheck
        self.permissionRequest = permissionRequest
        self.postEvent = postEvent
    }

    public var isAuthorized: Bool { trustCheck() }

    @discardableResult
    public func requestAuthorization() -> Bool { permissionRequest() }

    public func beginCommand() throws {
        guard !releasePending else { throw MacCommandTabError.releasePending }
        guard trustCheck() else { throw MacCommandTabError.accessibilityPermissionRequired }
        guard !isHoldingCommand else { return }
        guard postEvent(.commandDown) else { throw MacCommandTabError.eventPostFailed }
        isHoldingCommand = true
    }

    public func pressTab() throws {
        guard !releasePending else { throw MacCommandTabError.releasePending }
        guard trustCheck() else { throw MacCommandTabError.accessibilityPermissionRequired }
        let commandHeld = isHoldingCommand
        guard postEvent(.tabDown(commandHeld: commandHeld)) else {
            throw MacCommandTabError.eventPostFailed
        }
        isHoldingTab = true
        guard postEvent(.tabUp(commandHeld: commandHeld)) else {
            throw MacCommandTabError.eventPostFailed
        }
        isHoldingTab = false
    }

    @discardableResult
    public func releaseAll() -> Bool {
        if isHoldingTab {
            guard postEvent(.tabUp(commandHeld: isHoldingCommand)) else { return false }
            isHoldingTab = false
        }
        if isHoldingCommand {
            guard postEvent(.commandUp) else {
                commandReleasePending = true
                return false
            }
            isHoldingCommand = false
            commandReleasePending = false
        }
        return true
    }

    private static func postSystemEvent(_ event: MacCommandTabEvent) -> Bool {
        let keyCode: CGKeyCode
        let keyDown: Bool
        let flags: CGEventFlags
        switch event {
        case .commandDown:
            (keyCode, keyDown, flags) = (55, true, .maskCommand)
        case .tabDown(let commandHeld):
            (keyCode, keyDown, flags) = (48, true, commandHeld ? .maskCommand : [])
        case .tabUp(let commandHeld):
            (keyCode, keyDown, flags) = (48, false, commandHeld ? .maskCommand : [])
        case .commandUp:
            (keyCode, keyDown, flags) = (55, false, [])
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyboardEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: keyDown
              ) else { return false }
        keyboardEvent.flags = flags
        keyboardEvent.post(tap: .cghidEventTap)
        return true
    }
}
