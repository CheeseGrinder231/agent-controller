import Testing
@testable import AgentControllerCore

@Test func replacementRejectsEveryStaleControllerEvent() {
    var gate = ControllerEventSourceGate()
    gate.activate("controller-a")
    #expect(gate.allows("controller-a"))

    gate.activate("controller-b")

    #expect(!gate.allows("controller-a"))
    #expect(gate.allows("controller-b"))
}

@Test func deactivationRejectsDelayedEventsFromTheFormerController() {
    var gate = ControllerEventSourceGate()
    gate.activate("controller-a")
    gate.deactivate()

    #expect(!gate.allows("controller-a"))
}
