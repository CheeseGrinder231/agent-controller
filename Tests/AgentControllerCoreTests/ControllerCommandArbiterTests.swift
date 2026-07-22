import Testing
@testable import AgentControllerCore

@Test func idleAllowsEveryCommandDomain() {
    let idle = ControllerCommandActivity(
        appLocalCommandActive: false,
        commandModifierHeld: false,
        releasePending: false
    )

    for intent in [
        ControllerCommandIntent.sessionPicker,
        .projectStarter,
        .dictation,
        .stop,
        .commandModifier,
        .tabPulse,
        .enterPulse,
        .sessionScroll,
        .showConsole,
    ] {
        #expect(ControllerCommandArbiter.allows(intent, activity: idle))
    }
}

@Test func heldCommandAllowsOnlyComposablePulses() {
    let commandHeld = ControllerCommandActivity(
        appLocalCommandActive: false,
        commandModifierHeld: true,
        releasePending: false
    )

    #expect(ControllerCommandArbiter.allows(.tabPulse, activity: commandHeld))
    #expect(ControllerCommandArbiter.allows(.enterPulse, activity: commandHeld))
    #expect(!ControllerCommandArbiter.allows(.sessionPicker, activity: commandHeld))
    #expect(!ControllerCommandArbiter.allows(.projectStarter, activity: commandHeld))
    #expect(!ControllerCommandArbiter.allows(.dictation, activity: commandHeld))
    #expect(!ControllerCommandArbiter.allows(.commandModifier, activity: commandHeld))
    #expect(!ControllerCommandArbiter.allows(.showConsole, activity: commandHeld))
    #expect(!ControllerCommandArbiter.allows(.stop, activity: commandHeld))
    #expect(!ControllerCommandArbiter.allows(.sessionScroll, activity: commandHeld))
}

@Test func appLocalActivityBlocksGlobalAndOtherLocalCommands() {
    let appLocal = ControllerCommandActivity(
        appLocalCommandActive: true,
        commandModifierHeld: false,
        releasePending: false
    )

    #expect(!ControllerCommandArbiter.allows(.tabPulse, activity: appLocal))
    #expect(!ControllerCommandArbiter.allows(.commandModifier, activity: appLocal))
    #expect(!ControllerCommandArbiter.allows(.sessionPicker, activity: appLocal))
    #expect(!ControllerCommandArbiter.allows(.projectStarter, activity: appLocal))
    #expect(!ControllerCommandArbiter.allows(.dictation, activity: appLocal))
    #expect(!ControllerCommandArbiter.allows(.showConsole, activity: appLocal))
}

@Test func pendingReleaseBlocksEveryNewCommand() {
    let pending = ControllerCommandActivity(
        appLocalCommandActive: false,
        commandModifierHeld: false,
        releasePending: true
    )

    for intent in [
        ControllerCommandIntent.sessionPicker,
        .projectStarter,
        .dictation,
        .stop,
        .commandModifier,
        .tabPulse,
        .enterPulse,
        .sessionScroll,
        .showConsole,
    ] {
        #expect(!ControllerCommandArbiter.allows(intent, activity: pending))
    }
}

@Test func bindingCaptureBlocksEveryControllerCommand() {
    let recording = ControllerCommandActivity(
        appLocalCommandActive: false,
        commandModifierHeld: false,
        releasePending: false,
        recordingBinding: true
    )

    for intent in [
        ControllerCommandIntent.sessionPicker,
        .projectStarter,
        .dictation,
        .stop,
        .commandModifier,
        .tabPulse,
        .enterPulse,
        .sessionScroll,
        .showConsole,
    ] {
        #expect(!ControllerCommandArbiter.allows(intent, activity: recording))
    }
}
