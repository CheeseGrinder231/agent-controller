import Testing
@testable import AgentControllerMac

@MainActor
@Test func commandHoldAndRepeatedTabPulsesPostExactSequence() throws {
    var events: [MacCommandTabEvent] = []
    let adapter = commandTabAdapter { event in
        events.append(event)
        return true
    }

    try adapter.beginCommand()
    try adapter.beginCommand()
    try adapter.pressTab()
    try adapter.pressTab()
    #expect(adapter.releaseAll())
    #expect(adapter.releaseAll())

    #expect(events == [
        .commandDown,
        .tabDown(commandHeld: true),
        .tabUp(commandHeld: true),
        .tabDown(commandHeld: true),
        .tabUp(commandHeld: true),
        .commandUp,
    ])
}

@MainActor
@Test func tabWithoutCommandPostsOneCompletePulse() throws {
    var events: [MacCommandTabEvent] = []
    let adapter = commandTabAdapter { event in
        events.append(event)
        return true
    }

    try adapter.pressTab()

    #expect(events == [.tabDown(commandHeld: false), .tabUp(commandHeld: false)])
    #expect(!adapter.releasePending)
}

@MainActor
@Test func focusChangesDoNotAffectHeldCommand() throws {
    var events: [MacCommandTabEvent] = []
    let adapter = commandTabAdapter { event in
        events.append(event)
        return true
    }

    try adapter.beginCommand()
    try adapter.pressTab()
    try adapter.pressTab()
    #expect(adapter.isHoldingCommand)
    #expect(adapter.releaseAll())
    #expect(events.last == .commandUp)
}

@MainActor
@Test func failedTabReleaseStaysPendingAndBlocksNewInput() throws {
    var tabUpAttempts = 0
    let adapter = commandTabAdapter { event in
        if case .tabUp = event {
            tabUpAttempts += 1
            return tabUpAttempts > 1
        }
        return true
    }

    #expect(throws: MacCommandTabError.eventPostFailed) { try adapter.pressTab() }
    #expect(adapter.isHoldingTab)
    #expect(adapter.releasePending)
    #expect(throws: MacCommandTabError.releasePending) { try adapter.pressTab() }
    #expect(adapter.releaseAll())
    #expect(!adapter.releasePending)
}

@MainActor
@Test func failedCommandReleaseStaysRetryableAndBlocksTab() throws {
    var commandUpAttempts = 0
    let adapter = commandTabAdapter { event in
        guard event == .commandUp else { return true }
        commandUpAttempts += 1
        return commandUpAttempts > 1
    }

    try adapter.beginCommand()
    #expect(!adapter.releaseAll())
    #expect(adapter.isHoldingCommand)
    #expect(throws: MacCommandTabError.releasePending) {
        try adapter.beginCommand()
    }
    #expect(adapter.releaseAll())
    #expect(!adapter.releasePending)
}

@MainActor
@Test func permissionFailurePostsNothing() {
    var events: [MacCommandTabEvent] = []
    let adapter = MacCommandTabAdapter(
        trustCheck: { false },
        permissionRequest: { false },
        postEvent: { event in
            events.append(event)
            return true
        }
    )

    #expect(throws: MacCommandTabError.accessibilityPermissionRequired) {
        try adapter.beginCommand()
    }
    #expect(throws: MacCommandTabError.accessibilityPermissionRequired) {
        try adapter.pressTab()
    }
    #expect(events.isEmpty)
}

@MainActor
private func commandTabAdapter(
    postEvent: @escaping (MacCommandTabEvent) -> Bool
) -> MacCommandTabAdapter {
    MacCommandTabAdapter(
        trustCheck: { true },
        permissionRequest: { true },
        postEvent: postEvent
    )
}
