import Testing
@testable import AgentControllerCore

@Test func newerCommitInvalidatesAnOlderCommit() {
    var gate = SessionCommitGate()
    let first = gate.begin()
    let second = gate.begin()

    #expect(!gate.isCurrent(first))
    #expect(gate.isCurrent(second))
}

@Test func cancellationInvalidatesTheCurrentCommit() {
    var gate = SessionCommitGate()
    let token = gate.begin()

    gate.invalidate()

    #expect(!gate.isCurrent(token))
}
