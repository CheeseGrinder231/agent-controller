import Testing
@testable import AgentControllerCore

@Test func scrollRequiresNeutralAfterActivation() {
    var interpreter = AnalogScrollInterpreter()
    let configuration = AnalogScrollConfiguration.default

    interpreter.activate(currentX: 0, currentY: 0.8)
    interpreter.update(x: 0, y: 0.8, configuration: configuration)
    #expect(interpreter.delta(elapsed: 1.0 / 60.0) == 0)

    interpreter.update(x: 0, y: 0, configuration: configuration)
    interpreter.update(x: 0, y: 0.8, configuration: configuration)
    #expect(interpreter.delta(elapsed: 1.0 / 60.0) > 0)
}

@Test func scrollUsesDeadZoneVerticalIntentAndQuadraticSpeed() {
    var interpreter = AnalogScrollInterpreter()
    let configuration = AnalogScrollConfiguration(enabled: true, inverted: false, speed: 1)
    interpreter.activate(currentX: 0, currentY: 0)

    interpreter.update(x: 0, y: 0.19, configuration: configuration)
    #expect(interpreter.delta(elapsed: 1) == 0)
    interpreter.update(x: 0.6, y: 0.6, configuration: configuration)
    #expect(interpreter.delta(elapsed: 1) == 0)
    interpreter.update(x: 0, y: 0.4, configuration: configuration)
    let slow = interpreter.delta(elapsed: 1)
    interpreter.update(x: 0, y: 1, configuration: configuration)
    let fast = interpreter.delta(elapsed: 1)
    #expect(slow >= 120)
    #expect(fast > slow)
}

@Test func scrollInvertsAndStopsAtNeutralOrDeactivation() {
    var interpreter = AnalogScrollInterpreter()
    interpreter.activate(currentX: 0, currentY: 0)
    interpreter.update(
        x: 0,
        y: 1,
        configuration: AnalogScrollConfiguration(enabled: true, inverted: true, speed: 0.5)
    )
    #expect(interpreter.delta(elapsed: 1.0 / 60.0) < 0)

    interpreter.update(x: 0, y: 0, configuration: .default)
    #expect(interpreter.delta(elapsed: 1) == 0)
    interpreter.deactivate()
    #expect(interpreter.delta(elapsed: 1) == 0)
}
