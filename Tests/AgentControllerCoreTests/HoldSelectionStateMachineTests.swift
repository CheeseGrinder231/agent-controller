import Testing
@testable import AgentControllerCore

private let codex = ApplicationContext(
    processIdentifier: 42,
    bundleIdentifier: "com.openai.codex",
    displayName: "Codex"
)

private let sessionIDs = [
    "019f7e48-66f8-7192-8446-d4e2cf9ae0e6",
    "019f7e48-66f8-7192-8446-d4e2cf9ae0e7",
    "019f7e48-66f8-7192-8446-d4e2cf9ae0e8",
]

@Test func profileRegistryAllowsOnlyExactCodexBundle() {
    #expect(ProfileRegistry.supports(codex))
    #expect(!ProfileRegistry.supports(ApplicationContext(
        processIdentifier: 43,
        bundleIdentifier: "com.openai.chat",
        displayName: "ChatGPT"
    )))
}

@Test func quickTapCancelsWithoutPreview() {
    var machine = HoldSelectionStateMachine()
    #expect(machine.begin(
        at: 0,
        context: codex,
        controllerIdentifier: "one",
        itemIDs: sessionIDs,
        isArmed: true
    ) == .none)
    #expect(machine.release(
        currentContext: codex,
        controllerIdentifier: "one"
    ) == .cancelled(.earlyRelease))
}

@Test func holdWithoutDirectionalChoiceCancels() {
    var machine = startedMachine()
    #expect(machine.activatePreview(at: 0.25) == .showPreview)
    #expect(machine.release(
        currentContext: codex,
        controllerIdentifier: "one"
    ) == .cancelled(.noSelection))
}

@Test func verticalSelectionCyclesAndCommitsExactSessionOnce() {
    var machine = startedMachine()
    _ = machine.activatePreview(at: 0.3)

    #expect(machine.move(.down) == .selectionChanged(0))
    #expect(machine.move(.down) == .selectionChanged(1))
    #expect(machine.release(
        currentContext: codex,
        controllerIdentifier: "one"
    ) == .commitSelection(sessionIDs[1], codex))
    #expect(machine.release(currentContext: codex, controllerIdentifier: "one") == .none)
}

@Test func upwardSelectionStartsAtLastSessionAndWraps() {
    var machine = startedMachine()
    _ = machine.activatePreview(at: 0.3)

    #expect(machine.move(.up) == .selectionChanged(2))
    #expect(machine.move(.up) == .selectionChanged(1))
}

@Test func gestureUsesItsFrozenSessionOrdering() {
    var machine = startedMachine(ids: [sessionIDs[2], sessionIDs[0]])
    _ = machine.activatePreview(at: 0.3)
    _ = machine.move(.down)

    #expect(machine.release(
        currentContext: codex,
        controllerIdentifier: "one"
    ) == .commitSelection(sessionIDs[2], codex))
}

@Test func exactProjectPathUsesTheSameFrozenHoldSelectionContract() {
    let projectPaths = ["/tmp/alpha", "/tmp/beta"]
    var machine = HoldSelectionStateMachine()
    _ = machine.begin(
        at: 0,
        context: codex,
        controllerIdentifier: "one",
        itemIDs: projectPaths,
        isArmed: true
    )
    _ = machine.activatePreview(at: 0.3)
    _ = machine.move(.down)
    _ = machine.move(.down)

    #expect(machine.release(
        currentContext: codex,
        controllerIdentifier: "one"
    ) == .commitSelection("/tmp/beta", codex))
    #expect(machine.release(currentContext: codex, controllerIdentifier: "one") == .none)
}

@Test func emptyInventoryCannotSelectOrCommit() {
    var machine = startedMachine(ids: [])
    _ = machine.activatePreview(at: 0.3)

    #expect(machine.move(.down) == .none)
    #expect(machine.release(
        currentContext: codex,
        controllerIdentifier: "one"
    ) == .cancelled(.noSelection))
}

@Test func focusChangeFailsClosed() {
    var machine = startedMachine()
    _ = machine.activatePreview(at: 0.3)
    _ = machine.move(.down)

    let terminal = ApplicationContext(
        processIdentifier: 99,
        bundleIdentifier: "com.apple.Terminal",
        displayName: "Terminal"
    )
    #expect(machine.cancelIfContextChanged(to: terminal) == .cancelled(.focusChanged))
    #expect(machine.phase == .idle)
}

@Test func controllerChangeFailsClosed() {
    var machine = startedMachine()
    _ = machine.activatePreview(at: 0.3)
    _ = machine.move(.up)

    #expect(machine.release(
        currentContext: codex,
        controllerIdentifier: "two"
    ) == .cancelled(.controllerChanged))
}

@Test func dpadMovementBeforePreviewDoesNothing() {
    var machine = startedMachine()

    #expect(machine.move(.down) == .none)
    #expect(machine.selectedIndex == nil)
}

@Test func disconnectCancelsAnActiveGesture() {
    var machine = startedMachine()
    _ = machine.activatePreview(at: 0.3)

    #expect(machine.cancel(.controllerDisconnected) == .cancelled(.controllerDisconnected))
    #expect(machine.phase == .idle)
}

@Test func twentyRepeatedGesturesEachCommitOnce() {
    for iteration in 0..<20 {
        var machine = HoldSelectionStateMachine()
        let controller = "controller-\(iteration)"
        _ = machine.begin(
            at: 0,
            context: codex,
            controllerIdentifier: controller,
            itemIDs: sessionIDs,
            isArmed: true
        )
        _ = machine.activatePreview(at: 0.3)
        _ = machine.move(.down)

        #expect(machine.release(
            currentContext: codex,
            controllerIdentifier: controller
        ) == .commitSelection(sessionIDs[0], codex))
        #expect(machine.release(currentContext: codex, controllerIdentifier: controller) == .none)
    }
}

@Test func disarmedAndUnsupportedContextsNeverStart() {
    var machine = HoldSelectionStateMachine()
    #expect(machine.begin(
        at: 0,
        context: codex,
        controllerIdentifier: "one",
        itemIDs: sessionIDs,
        isArmed: false
    ) == .cancelled(.disarmed))
    #expect(machine.phase == .idle)
    #expect(machine.begin(
        at: 0,
        context: nil,
        controllerIdentifier: "one",
        itemIDs: sessionIDs,
        isArmed: true
    ) == .cancelled(.unsupportedApplication))
    #expect(machine.phase == .idle)
}

private func startedMachine(ids: [String] = sessionIDs) -> HoldSelectionStateMachine {
    var machine = HoldSelectionStateMachine()
    _ = machine.begin(
        at: 0,
        context: codex,
        controllerIdentifier: "one",
        itemIDs: ids,
        isArmed: true
    )
    return machine
}
