import Testing
@testable import AgentControllerCore

private let voiceCodex = ApplicationContext(
    processIdentifier: 42,
    bundleIdentifier: "com.openai.codex",
    displayName: "Codex"
)

@Test func rbBeginsAndReleaseEndsDictationExactlyOnce() {
    var machine = VoiceHoldStateMachine()

    #expect(machine.begin(
        context: voiceCodex,
        controllerIdentifier: "one",
        isArmed: true
    ) == .beginDictation(voiceCodex))
    #expect(machine.begin(
        context: voiceCodex,
        controllerIdentifier: "one",
        isArmed: true
    ) == .none)
    #expect(machine.release(
        currentContext: voiceCodex,
        controllerIdentifier: "one"
    ) == .endDictation)
    #expect(machine.release(currentContext: voiceCodex, controllerIdentifier: "one") == .none)
}

@Test func voiceHoldRequiresArmedExactCodexContext() {
    var machine = VoiceHoldStateMachine()
    let terminal = ApplicationContext(
        processIdentifier: 99,
        bundleIdentifier: "com.apple.Terminal",
        displayName: "Terminal"
    )

    #expect(machine.begin(
        context: voiceCodex,
        controllerIdentifier: "one",
        isArmed: false
    ) == .cancelled(.disarmed, shouldEndDictation: false))
    #expect(machine.begin(
        context: terminal,
        controllerIdentifier: "one",
        isArmed: true
    ) == .cancelled(.unsupportedApplication, shouldEndDictation: false))
    #expect(machine.phase == .idle)
}

@Test func focusChangeEndsAnActiveVoiceHold() {
    var machine = startedVoiceMachine()
    let terminal = ApplicationContext(
        processIdentifier: 99,
        bundleIdentifier: "com.apple.Terminal",
        displayName: "Terminal"
    )

    #expect(machine.cancelIfContextChanged(to: terminal) == .cancelled(
        .focusChanged,
        shouldEndDictation: true
    ))
    #expect(machine.phase == .idle)
}

@Test func controllerMismatchAndDisconnectEndDictation() {
    var controllerMismatch = startedVoiceMachine()
    #expect(controllerMismatch.release(
        currentContext: voiceCodex,
        controllerIdentifier: "two"
    ) == .cancelled(.controllerChanged, shouldEndDictation: true))

    var disconnected = startedVoiceMachine()
    #expect(disconnected.cancel(.controllerDisconnected) == .cancelled(
        .controllerDisconnected,
        shouldEndDictation: true
    ))
}

private func startedVoiceMachine() -> VoiceHoldStateMachine {
    var machine = VoiceHoldStateMachine()
    _ = machine.begin(
        context: voiceCodex,
        controllerIdentifier: "one",
        isArmed: true
    )
    return machine
}
