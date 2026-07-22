import AgentControllerCore
import AppKit
import ApplicationServices
import Foundation

public struct VoiceInputContract: Equatable, Sendable {
    public let semanticAction: String
    public let adapterIdentifier: String
    public let targetBundleIdentifier: String
    public let shortcutDescription: String

    public init(
        semanticAction: String,
        adapterIdentifier: String,
        targetBundleIdentifier: String,
        shortcutDescription: String
    ) {
        self.semanticAction = semanticAction
        self.adapterIdentifier = adapterIdentifier
        self.targetBundleIdentifier = targetBundleIdentifier
        self.shortcutDescription = shortcutDescription
    }
}

public enum VoiceInputAdapterError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case unsupportedApplication
    case focusChanged
    case eventCreationFailed
    case releasePending
}

@MainActor
public final class CodexDictationShortcutAdapter {
    public static let contract = VoiceInputContract(
        semanticAction: "pushToTalk",
        adapterIdentifier: "codex.composer.startDictation-shortcut",
        targetBundleIdentifier: ProfileRegistry.codexBundleIdentifier,
        shortcutDescription: "Configurable; default Control+Shift+D"
    )

    public private(set) var isHolding = false
    public private(set) var shortcut = CodexKeyboardShortcut.defaultDictation

    private let trustCheck: () -> Bool
    private let permissionRequest: () -> Bool
    private let currentContext: () -> ApplicationContext?
    private let postKeyEvent: (
        _ processIdentifier: Int32,
        _ shortcut: CodexKeyboardShortcut,
        _ keyDown: Bool
    ) -> Bool
    private var holdingProcessIdentifier: Int32?
    private var holdingShortcut: CodexKeyboardShortcut?

    public convenience init() {
        self.init(
            trustCheck: { AXIsProcessTrusted() },
            permissionRequest: {
                AXIsProcessTrustedWithOptions(
                    ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                )
            },
            currentContext: {
                guard let application = NSWorkspace.shared.frontmostApplication,
                      let bundleIdentifier = application.bundleIdentifier else { return nil }
                return ApplicationContext(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    displayName: application.localizedName ?? bundleIdentifier
                )
            },
            postKeyEvent: { processIdentifier, shortcut, keyDown in
                Self.postDictationChord(
                    processIdentifier: processIdentifier,
                    shortcut: shortcut,
                    keyDown: keyDown
                )
            }
        )
    }

    init(
        trustCheck: @escaping () -> Bool,
        permissionRequest: @escaping () -> Bool,
        currentContext: @escaping () -> ApplicationContext?,
        postKeyEvent: @escaping (_ processIdentifier: Int32, _ keyDown: Bool) -> Bool
    ) {
        self.trustCheck = trustCheck
        self.permissionRequest = permissionRequest
        self.currentContext = currentContext
        self.postKeyEvent = { processIdentifier, _, keyDown in
            postKeyEvent(processIdentifier, keyDown)
        }
    }

    init(
        trustCheck: @escaping () -> Bool,
        permissionRequest: @escaping () -> Bool,
        currentContext: @escaping () -> ApplicationContext?,
        postKeyEvent: @escaping (
            _ processIdentifier: Int32,
            _ shortcut: CodexKeyboardShortcut,
            _ keyDown: Bool
        ) -> Bool
    ) {
        self.trustCheck = trustCheck
        self.permissionRequest = permissionRequest
        self.currentContext = currentContext
        self.postKeyEvent = postKeyEvent
    }

    public var isAuthorized: Bool {
        trustCheck()
    }

    @discardableResult
    public func requestAuthorization() -> Bool {
        permissionRequest()
    }

    @discardableResult
    public func updateShortcut(_ shortcut: CodexKeyboardShortcut) -> Bool {
        guard !isHolding else { return false }
        self.shortcut = shortcut
        return true
    }

    public func begin(frozenContext: ApplicationContext) throws {
        guard !isHolding else { throw VoiceInputAdapterError.releasePending }
        guard frozenContext.bundleIdentifier == Self.contract.targetBundleIdentifier else {
            throw VoiceInputAdapterError.unsupportedApplication
        }
        guard currentContext() == frozenContext else {
            throw VoiceInputAdapterError.focusChanged
        }
        guard isAuthorized else {
            throw VoiceInputAdapterError.accessibilityPermissionRequired
        }
        guard currentContext() == frozenContext else {
            throw VoiceInputAdapterError.focusChanged
        }
        let shortcut = self.shortcut
        guard postKeyEvent(frozenContext.processIdentifier, shortcut, true) else {
            throw VoiceInputAdapterError.eventCreationFailed
        }
        holdingProcessIdentifier = frozenContext.processIdentifier
        holdingShortcut = shortcut
        isHolding = true
    }

    @discardableResult
    public func end() -> Bool {
        guard isHolding, let holdingProcessIdentifier, let holdingShortcut else { return true }
        let posted = postKeyEvent(holdingProcessIdentifier, holdingShortcut, false)
        guard posted else { return false }
        isHolding = false
        self.holdingProcessIdentifier = nil
        self.holdingShortcut = nil
        return true
    }

    private static func postDictationChord(
        processIdentifier: Int32,
        shortcut: CodexKeyboardShortcut,
        keyDown: Bool
    ) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        var definitions: [(CGKeyCode, Bool, CGEventFlags)] = []
        if keyDown {
            for modifier in shortcut.modifiers {
                flags.insert(modifier.eventFlag)
                definitions.append((modifier.keyCode, true, flags))
            }
            definitions.append((shortcut.key.keyCode, true, flags))
        } else {
            flags = shortcut.modifiers.reduce(into: CGEventFlags()) {
                $0.insert($1.eventFlag)
            }
            definitions.append((shortcut.key.keyCode, false, flags))
            for modifier in shortcut.modifiers.reversed() {
                flags.remove(modifier.eventFlag)
                definitions.append((modifier.keyCode, false, flags))
            }
        }

        let events = definitions.compactMap { keyCode, isDown, flags -> CGEvent? in
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: isDown
            ) else { return nil }
            event.flags = flags
            return event
        }
        guard events.count == definitions.count else { return false }
        events.forEach { $0.postToPid(processIdentifier) }
        return true
    }
}
