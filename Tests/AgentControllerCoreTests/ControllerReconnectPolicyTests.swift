import Testing
@testable import AgentControllerCore

@Test func freshConnectionDoesNotEnableControllerCommands() {
    var policy = ControllerReconnectPolicy()
    let shouldEnable = policy.controllerConnected()

    #expect(!shouldEnable)
}

@Test func enabledControllerResumesAfterReconnectExactlyOnce() {
    var policy = ControllerReconnectPolicy()
    policy.controllerDisconnected(wasEnabled: true)
    let firstReconnect = policy.controllerConnected()
    let secondReconnect = policy.controllerConnected()

    #expect(firstReconnect)
    #expect(!secondReconnect)
}

@Test func pausedControllerStaysPausedAfterReconnect() {
    var policy = ControllerReconnectPolicy()
    policy.controllerDisconnected(wasEnabled: false)
    let shouldEnable = policy.controllerConnected()

    #expect(!shouldEnable)
}

@Test func pausingWhileDisconnectedCancelsAutomaticResume() {
    var policy = ControllerReconnectPolicy()
    policy.controllerDisconnected(wasEnabled: true)
    policy.userChangedEnablement(false)
    let shouldEnable = policy.controllerConnected()

    #expect(!shouldEnable)
}
