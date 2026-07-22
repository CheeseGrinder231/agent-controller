import AgentControllerCore
import ApplicationServices
import Testing
@testable import AgentControllerMac

@MainActor
@Test func ltAndAComposeOneExactCommandReturnSequence() throws {
    enum CombinedEvent: Equatable {
        case command(MacCommandTabEvent)
        case chord(CGKeyCode, Bool, Bool)
    }
    var events: [CombinedEvent] = []
    let command = MacCommandTabAdapter(
        trustCheck: { true },
        permissionRequest: { true },
        postEvent: {
            events.append(.command($0))
            return true
        }
    )
    let pulse = KeyboardChordPulseAdapter(
        trustCheck: { true },
        currentContext: { nil },
        postEvent: {
            events.append(.chord($0.keyCode, $0.keyDown, $0.flags.contains(.maskCommand)))
            return true
        }
    )

    try command.beginCommand()
    try pulse.pulseSystem(.defaultReturn, externalModifiers: [.command])
    #expect(command.releaseAll())

    #expect(events == [
        .command(.commandDown),
        .chord(36, true, true),
        .chord(36, false, true),
        .command(.commandUp),
    ])
}

@MainActor
@Test func targetedPulseRequiresExactFrozenCodexContext() throws {
    let codex = pulseCodex()
    var frontmost = codex
    var events: [KeyboardChordEvent] = []
    let adapter = KeyboardChordPulseAdapter(
        trustCheck: { true },
        currentContext: { frontmost },
        postEvent: {
            events.append($0)
            return true
        }
    )

    try adapter.pulse(
        .defaultEscape,
        frozenContext: codex,
        targetBundleIdentifier: ProfileRegistry.codexBundleIdentifier
    )
    #expect(events.map(\.target) == [.process(42), .process(42)])

    frontmost = ApplicationContext(
        processIdentifier: 99,
        bundleIdentifier: "com.apple.Terminal",
        displayName: "Terminal"
    )
    #expect(throws: KeyboardChordPulseError.focusChanged) {
        try adapter.pulse(
            .defaultEscape,
            frozenContext: codex,
            targetBundleIdentifier: ProfileRegistry.codexBundleIdentifier
        )
    }
    #expect(events.count == 2)
}

@MainActor
@Test func targetedSequencePostsThreeCompleteEscapePulses() async throws {
    let codex = pulseCodex()
    var events: [KeyboardChordEvent] = []
    let adapter = KeyboardChordPulseAdapter(
        trustCheck: { true },
        currentContext: { codex },
        postEvent: {
            events.append($0)
            return true
        }
    )

    try await adapter.pulseSequence(
        .defaultEscape,
        count: 3,
        interval: .zero,
        frozenContext: codex,
        targetBundleIdentifier: ProfileRegistry.codexBundleIdentifier
    )

    #expect(events.map(\.keyDown) == [true, false, true, false, true, false])
    #expect(events.allSatisfy { $0.keyCode == KeyboardChord.defaultEscape.key.keyCode })
    #expect(events.allSatisfy { $0.target == .process(codex.processIdentifier) })
}

@MainActor
@Test func targetedSequenceFailsClosedBeforeASecondPulseAfterFocusDrift() async {
    let codex = pulseCodex()
    var frontmost = codex
    var events: [KeyboardChordEvent] = []
    let adapter = KeyboardChordPulseAdapter(
        trustCheck: { true },
        currentContext: { frontmost },
        postEvent: {
            events.append($0)
            if events.count == 2 {
                frontmost = ApplicationContext(
                    processIdentifier: 99,
                    bundleIdentifier: "com.apple.Safari",
                    displayName: "Safari"
                )
            }
            return true
        }
    )

    await #expect(throws: KeyboardChordPulseError.focusChanged) {
        try await adapter.pulseSequence(
            .defaultEscape,
            count: 3,
            interval: .zero,
            frozenContext: codex,
            targetBundleIdentifier: ProfileRegistry.codexBundleIdentifier
        )
    }
    #expect(events.map(\.keyDown) == [true, false])
}

@MainActor
@Test func failedPulseReleaseRemainsStickyAndRetryable() {
    var releaseAttempts = 0
    let adapter = KeyboardChordPulseAdapter(
        trustCheck: { true },
        currentContext: { nil },
        postEvent: { event in
            guard !event.keyDown else { return true }
            releaseAttempts += 1
            return releaseAttempts > 1
        }
    )

    #expect(throws: KeyboardChordPulseError.eventPostFailed) {
        try adapter.pulseSystem(.defaultReturn)
    }
    #expect(adapter.releasePending)
    #expect(throws: KeyboardChordPulseError.releasePending) {
        try adapter.pulseSystem(.defaultReturn)
    }
    #expect(adapter.releaseAll())
    #expect(!adapter.releasePending)
}

@MainActor
@Test func partialDownFailureReleasesOnlyKeysThatWereActuallyPosted() {
    var attempts: [KeyboardChordEvent] = []
    let adapter = KeyboardChordPulseAdapter(
        trustCheck: { true },
        currentContext: { nil },
        postEvent: { event in
            attempts.append(event)
            return attempts.count != 2
        }
    )
    let chord = KeyboardChord.defaultDictation.withTriggerMode(.pulse)

    #expect(throws: KeyboardChordPulseError.eventPostFailed) {
        try adapter.pulseSystem(chord)
    }
    #expect(adapter.releasePending)
    #expect(adapter.releaseAll())
    #expect(attempts.map(\.keyCode) == [59, 56, 59])
    #expect(attempts.map(\.keyDown) == [true, true, false])
}

private func pulseCodex() -> ApplicationContext {
    ApplicationContext(
        processIdentifier: 42,
        bundleIdentifier: ProfileRegistry.codexBundleIdentifier,
        displayName: "Codex"
    )
}
