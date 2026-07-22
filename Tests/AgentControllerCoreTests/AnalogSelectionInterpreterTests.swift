import Testing
@testable import AgentControllerCore

@Test func neutralStickMovesOnceOnVerticalEntryThenRepeatsAtFixedIntervals() {
    var interpreter = AnalogSelectionInterpreter()
    interpreter.activate(currentX: 0, currentY: 0)

    #expect(interpreter.update(x: 0.05, y: 0.82, at: 1) == .up)
    #expect(interpreter.update(x: 0.05, y: 0.90, at: 1.1) == nil)
    #expect(interpreter.repeatedMove(at: 1.39) == nil)
    #expect(interpreter.repeatedMove(at: 1.40) == .up)
    #expect(interpreter.repeatedMove(at: 1.55) == nil)
    #expect(interpreter.repeatedMove(at: 1.56) == .up)
}

@Test func preheldStickMustReturnNeutralBeforeSelecting() {
    var interpreter = AnalogSelectionInterpreter()
    interpreter.activate(currentX: 0, currentY: -1)

    #expect(interpreter.update(x: 0, y: -1, at: 0) == nil)
    #expect(interpreter.repeatedMove(at: 1) == nil)
    #expect(interpreter.update(x: 0, y: 0, at: 1.1) == nil)
    #expect(interpreter.update(x: 0, y: -0.8, at: 1.2) == .down)
}

@Test func horizontalAndDiagonalInputDoNotSelect() {
    var interpreter = AnalogSelectionInterpreter()
    interpreter.activate(currentX: 0, currentY: 0)

    #expect(interpreter.update(x: 0.9, y: 0.1, at: 0) == nil)
    #expect(interpreter.update(x: 0, y: 0, at: 0.1) == nil)
    #expect(interpreter.update(x: 0.72, y: 0.75, at: 0.2) == nil)
}

@Test func directionChangeRequiresNeutral() {
    var interpreter = AnalogSelectionInterpreter()
    interpreter.activate(currentX: 0, currentY: 0)
    #expect(interpreter.update(x: 0, y: 0.8, at: 0) == .up)

    #expect(interpreter.update(x: 0, y: -0.8, at: 0.1) == nil)
    #expect(interpreter.repeatedMove(at: 1) == nil)
    #expect(interpreter.update(x: 0, y: 0, at: 1.1) == nil)
    #expect(interpreter.update(x: 0, y: -0.8, at: 1.2) == .down)
}

@Test func dpadMovementCancelsRepeatAndSuppressesAHeldStick() {
    var interpreter = AnalogSelectionInterpreter()
    interpreter.activate(currentX: 0, currentY: 0)
    #expect(interpreter.update(x: 0, y: 0.8, at: 0) == .up)

    interpreter.dpadDidMove(currentX: 0, currentY: 0.8)

    #expect(interpreter.repeatedMove(at: 1) == nil)
    #expect(interpreter.update(x: 0, y: 0.8, at: 1.1) == nil)
    #expect(interpreter.update(x: 0, y: 0, at: 1.2) == nil)
    #expect(interpreter.update(x: 0, y: 0.8, at: 1.3) == .up)
}

@Test func deactivationCancelsSelectionAndRepeat() {
    var interpreter = AnalogSelectionInterpreter()
    interpreter.activate(currentX: 0, currentY: 0)
    #expect(interpreter.update(x: 0, y: -0.8, at: 0) == .down)

    interpreter.deactivate()

    #expect(interpreter.activeDirection == nil)
    #expect(interpreter.update(x: 0, y: -0.8, at: 1) == nil)
    #expect(interpreter.repeatedMove(at: 1) == nil)
}
