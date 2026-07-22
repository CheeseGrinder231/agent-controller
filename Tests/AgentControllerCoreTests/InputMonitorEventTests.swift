import AgentControllerCore
import Foundation
import Testing

@Test func inputMonitorStartsAndFinishesAnEvent() {
    var buffer = InputMonitorBuffer(capacity: 3)
    let startedAt = Date(timeIntervalSince1970: 100)
    let finishedAt = Date(timeIntervalSince1970: 101)

    let id = buffer.begin(
        input: .buttonX,
        gesture: .pressed,
        action: .stop,
        route: "Codex adapter",
        applicationName: "Codex",
        occurredAt: startedAt
    )
    buffer.finish(id, status: .completed, detail: "Stop command sent.", occurredAt: finishedAt)

    #expect(buffer.events == [
        InputMonitorEvent(
            id: id,
            occurredAt: finishedAt,
            input: .buttonX,
            gesture: .pressed,
            action: .stop,
            route: "Codex adapter",
            applicationName: "Codex",
            status: .completed,
            detail: "Stop command sent."
        )
    ])
}

@Test func inputMonitorKeepsNewestEventsWithinCapacity() {
    var buffer = InputMonitorBuffer(capacity: 2)

    let first = buffer.begin(
        input: .buttonA,
        gesture: .pressed,
        action: .enter,
        route: "Global keyboard",
        applicationName: "Finder"
    )
    let second = buffer.begin(
        input: .buttonB,
        gesture: .pressed,
        action: .cancel,
        route: "Controller",
        applicationName: "Finder"
    )
    let third = buffer.begin(
        input: .buttonY,
        gesture: .pressed,
        action: .showController,
        route: "Agent Controller",
        applicationName: "Finder"
    )

    #expect(buffer.events.map(\.id) == [third, second])
    #expect(!buffer.events.contains(where: { $0.id == first }))
}

@Test func inputMonitorIgnoresUnknownCompletionAndClears() {
    var buffer = InputMonitorBuffer()
    _ = buffer.begin(
        input: .rightShoulder,
        gesture: .pressed,
        action: .pushToTalk,
        route: "Codex keyboard",
        applicationName: "Codex"
    )

    buffer.finish(UUID(), status: .failed, detail: "Should not be inserted.")
    #expect(buffer.events.count == 1)

    buffer.clear()
    #expect(buffer.events.isEmpty)
}

@Test func sessionStarterHasStableControllerAndSemanticLabels() {
    #expect(ControllerInputControl.leftStickButton.displayName == "L3")
    #expect(ControllerSemanticAction.projectStarter.displayName == "Session Starter")
}
