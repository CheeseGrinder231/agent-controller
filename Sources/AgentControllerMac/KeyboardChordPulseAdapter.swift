import AgentControllerCore
import AppKit
import ApplicationServices
import Foundation

public enum KeyboardChordTarget: Equatable, Sendable {
    case system
    case process(Int32)
}

public struct KeyboardChordEvent: Equatable, Sendable {
    public let target: KeyboardChordTarget
    public let keyCode: CGKeyCode
    public let keyDown: Bool
    public let flags: CGEventFlags

    public init(
        target: KeyboardChordTarget,
        keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags
    ) {
        self.target = target
        self.keyCode = keyCode
        self.keyDown = keyDown
        self.flags = flags
    }
}

public enum KeyboardChordPulseError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case unsupportedApplication
    case focusChanged
    case releasePending
    case eventPostFailed
}

@MainActor
public final class KeyboardChordPulseAdapter {
    public private(set) var releasePending = false

    private let trustCheck: () -> Bool
    private let currentContext: () -> ApplicationContext?
    private let postEvent: (KeyboardChordEvent) -> Bool
    private var pendingReleaseEvents: [KeyboardChordEvent] = []

    private struct DownDefinition {
        let keyCode: CGKeyCode
        let modifier: KeyboardChord.Modifier?
    }

    public convenience init() {
        self.init(
            trustCheck: { AXIsProcessTrusted() },
            currentContext: {
                guard let application = NSWorkspace.shared.frontmostApplication,
                      let bundleIdentifier = application.bundleIdentifier else { return nil }
                return ApplicationContext(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    displayName: application.localizedName ?? bundleIdentifier
                )
            },
            postEvent: Self.post
        )
    }

    public init(
        trustCheck: @escaping () -> Bool,
        currentContext: @escaping () -> ApplicationContext?,
        postEvent: @escaping (KeyboardChordEvent) -> Bool
    ) {
        self.trustCheck = trustCheck
        self.currentContext = currentContext
        self.postEvent = postEvent
    }

    public func pulseSystem(
        _ chord: KeyboardChord,
        externalModifiers: Set<KeyboardChord.Modifier> = []
    ) throws {
        try pulse(chord, target: .system, externalModifiers: externalModifiers)
    }

    public func pulse(
        _ chord: KeyboardChord,
        frozenContext: ApplicationContext,
        targetBundleIdentifier: String
    ) throws {
        guard frozenContext.bundleIdentifier == targetBundleIdentifier else {
            throw KeyboardChordPulseError.unsupportedApplication
        }
        guard currentContext() == frozenContext else {
            throw KeyboardChordPulseError.focusChanged
        }
        try pulse(chord, target: .process(frozenContext.processIdentifier), externalModifiers: [])
    }

    /// Posts a bounded sequence of the same app-targeted chord. Codex Desktop's
    /// current Stop keyboard contract is staged: Escape may first focus the
    /// composer, then reveal the Stop confirmation, then commit it. Each pulse
    /// revalidates the exact frozen application before posting.
    public func pulseSequence(
        _ chord: KeyboardChord,
        count: Int,
        interval: Duration,
        frozenContext: ApplicationContext,
        targetBundleIdentifier: String
    ) async throws {
        guard (1...3).contains(count) else {
            throw KeyboardChordPulseError.eventPostFailed
        }
        for index in 0..<count {
            try Task.checkCancellation()
            try pulse(
                chord,
                frozenContext: frozenContext,
                targetBundleIdentifier: targetBundleIdentifier
            )
            if index < count - 1 {
                try await Task.sleep(for: interval)
            }
        }
    }

    @discardableResult
    public func releaseAll() -> Bool {
        guard releasePending else { return true }
        var remaining: [KeyboardChordEvent] = []
        for event in pendingReleaseEvents where !postEvent(event) {
            remaining.append(event)
        }
        pendingReleaseEvents = remaining
        releasePending = !remaining.isEmpty
        return !releasePending
    }

    private func pulse(
        _ chord: KeyboardChord,
        target: KeyboardChordTarget,
        externalModifiers: Set<KeyboardChord.Modifier>
    ) throws {
        guard !releasePending else { throw KeyboardChordPulseError.releasePending }
        guard trustCheck() else { throw KeyboardChordPulseError.accessibilityPermissionRequired }
        guard chord.triggerMode == .pulse else { throw KeyboardChordPulseError.eventPostFailed }

        let ownedModifiers = chord.modifiers.filter { !externalModifiers.contains($0) }
        var flags = flags(for: externalModifiers)
        var downEvents: [(event: KeyboardChordEvent, definition: DownDefinition)] = []
        for modifier in ownedModifiers {
            flags.insert(modifier.eventFlag)
            downEvents.append((
                KeyboardChordEvent(
                    target: target,
                    keyCode: modifier.keyCode,
                    keyDown: true,
                    flags: flags
                ),
                DownDefinition(keyCode: modifier.keyCode, modifier: modifier)
            ))
        }
        downEvents.append((
            KeyboardChordEvent(
                target: target,
                keyCode: chord.key.keyCode,
                keyDown: true,
                flags: flags
            ),
            DownDefinition(keyCode: chord.key.keyCode, modifier: nil)
        ))

        var postedDefinitions: [DownDefinition] = []
        for (event, definition) in downEvents {
            guard postEvent(event) else {
                if !postedDefinitions.isEmpty {
                    pendingReleaseEvents = makeReleaseEvents(
                        for: postedDefinitions,
                        target: target,
                        externalModifiers: externalModifiers
                    )
                    releasePending = true
                }
                throw KeyboardChordPulseError.eventPostFailed
            }
            postedDefinitions.append(definition)
        }
        let releaseEvents = makeReleaseEvents(
            for: postedDefinitions,
            target: target,
            externalModifiers: externalModifiers
        )
        for (index, event) in releaseEvents.enumerated() {
            guard postEvent(event) else {
                pendingReleaseEvents = Array(releaseEvents[index...])
                releasePending = true
                throw KeyboardChordPulseError.eventPostFailed
            }
        }
    }

    private func makeReleaseEvents(
        for downDefinitions: [DownDefinition],
        target: KeyboardChordTarget,
        externalModifiers: Set<KeyboardChord.Modifier>
    ) -> [KeyboardChordEvent] {
        var activeModifiers = externalModifiers
        for definition in downDefinitions {
            if let modifier = definition.modifier { activeModifiers.insert(modifier) }
        }

        return downDefinitions.reversed().map { definition in
            if let modifier = definition.modifier { activeModifiers.remove(modifier) }
            return KeyboardChordEvent(
                target: target,
                keyCode: definition.keyCode,
                keyDown: false,
                flags: flags(for: activeModifiers)
            )
        }
    }

    private func flags(for modifiers: Set<KeyboardChord.Modifier>) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { $0.insert($1.eventFlag) }
    }

    private static func post(_ definition: KeyboardChordEvent) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: definition.keyCode,
                keyDown: definition.keyDown
              ) else { return false }
        event.flags = definition.flags
        switch definition.target {
        case .system:
            event.post(tap: .cghidEventTap)
        case .process(let processIdentifier):
            event.postToPid(processIdentifier)
        }
        return true
    }
}
