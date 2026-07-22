import AgentControllerCore
import Foundation
import GameController

@MainActor
final class ControllerMonitor {
    var onConnectionChanged: ((String?) -> Void)?
    var onHoldChanged: ((String, Bool) -> Void)?
    var onProjectHoldChanged: ((String, Bool) -> Void)?
    var onCommandHoldChanged: ((String, Bool) -> Void)?
    var onTabPressed: ((String) -> Void)?
    var onEnterPressed: ((String) -> Void)?
    var onDictationHoldChanged: ((String, Bool) -> Void)?
    var onStopInputObserved: (() -> Void)?
    var onStopPressed: ((String) -> Void)?
    var onSessionScroll: ((Int32) -> Void)?
    var onMove: ((ControllerInputControl, SelectionDirection) -> Void)?
    var onCancel: (() -> Void)?
    var onDisconnectActive: (() -> Void)?
    var onShowConsole: (() -> Void)?

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private weak var activeController: GCController?
    private var analogInterpreter = AnalogSelectionInterpreter()
    private var analogRepeatTask: Task<Void, Never>?
    private var scrollInterpreter = AnalogScrollInterpreter()
    private var scrollConfiguration = AnalogScrollConfiguration.default
    private var scrollTask: Task<Void, Never>?
    private var scrollTaskGeneration: UInt64 = 0
    private var scrollingEnabled = false
    private var eventSourceGate = ControllerEventSourceGate()

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        let center = NotificationCenter.default
        connectObserver = center.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileControllers() }
        }
        disconnectObserver = center.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileControllers() }
        }

        if let connected = GCController.controllers().first {
            attachIfNeeded(connected)
        } else {
            onConnectionChanged?(nil)
        }
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    func stop() {
        let center = NotificationCenter.default
        if let connectObserver { center.removeObserver(connectObserver) }
        if let disconnectObserver { center.removeObserver(disconnectObserver) }
        connectObserver = nil
        disconnectObserver = nil
        analogRepeatTask?.cancel()
        analogRepeatTask = nil
        analogInterpreter.deactivate()
        stopSessionScrolling()
        detach(activeController)
        eventSourceGate.deactivate()
        activeController = nil
        GCController.stopWirelessControllerDiscovery()
    }

    func setSelectorNavigationActive(_ isActive: Bool) {
        analogRepeatTask?.cancel()
        analogRepeatTask = nil
        guard isActive, let stick = activeController?.extendedGamepad?.leftThumbstick else {
            analogInterpreter.deactivate()
            return
        }
        analogInterpreter.activate(currentX: stick.xAxis.value, currentY: stick.yAxis.value)
    }

    func setSessionScrollingActive(
        _ isActive: Bool,
        configuration: AnalogScrollConfiguration
    ) {
        scrollConfiguration = configuration
        guard scrollingEnabled != isActive else { return }
        scrollingEnabled = isActive
        guard isActive, let stick = activeController?.extendedGamepad?.rightThumbstick else {
            stopSessionScrolling()
            return
        }
        scrollInterpreter.activate(currentX: stick.xAxis.value, currentY: stick.yAxis.value)
    }

    func requireSessionScrollNeutral() {
        cancelScrollTask()
        scrollInterpreter.deactivate()
        guard scrollingEnabled,
              let stick = activeController?.extendedGamepad?.rightThumbstick else { return }
        scrollInterpreter.activate(currentX: stick.xAxis.value, currentY: stick.yAxis.value)
    }

    private func attachIfNeeded(_ controller: GCController) {
        guard activeController == nil, let gamepad = controller.extendedGamepad else { return }
        activeController = controller
        let identifier = identifier(for: controller)
        eventSourceGate.activate(identifier)
        onConnectionChanged?(controller.vendorName ?? "Game controller")

        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.onHoldChanged?(identifier, pressed) }
            }
        }
        configureProjectStarterHandler(gamepad, identifier: identifier)
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.onCommandHoldChanged?(identifier, pressed) }
            }
        }
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.onTabPressed?(identifier) }
            }
        }
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.onEnterPressed?(identifier) }
            }
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.onDictationHoldChanged?(identifier, pressed) }
            }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.onStopInputObserved?()
                self?.dispatchIfActive(identifier) { $0.onStopPressed?(identifier) }
            }
        }
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.handleDpad(.up) }
            }
        }
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.handleDpad(.down) }
            }
        }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.handleAnalog(x: x, y: y) }
            }
        }
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.handleScrollAnalog(x: x, y: y) }
            }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.onCancel?() }
            }
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.onShowConsole?() }
            }
        }
    }

    private func configureProjectStarterHandler(
        _ gamepad: GCExtendedGamepad,
        identifier: String
    ) {
        gamepad.leftThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.dispatchIfActive(identifier) { $0.onProjectHoldChanged?(identifier, pressed) }
            }
        }
    }

    private func reconcileControllers() {
        let connected = GCController.controllers()
        if let activeController, connected.contains(where: { $0 === activeController }) {
            return
        }

        if activeController != nil {
            onDisconnectActive?()
        }
        analogRepeatTask?.cancel()
        analogRepeatTask = nil
        analogInterpreter.deactivate()
        stopSessionScrolling()
        detach(activeController)
        eventSourceGate.deactivate()
        activeController = nil
        if let replacement = connected.first {
            attachIfNeeded(replacement)
        } else {
            onConnectionChanged?(nil)
        }
    }

    private func identifier(for controller: GCController) -> String {
        "\(controller.vendorName ?? "controller"):\(ObjectIdentifier(controller))"
    }

    private func dispatchIfActive(
        _ controllerIdentifier: String,
        action: (ControllerMonitor) -> Void
    ) {
        guard eventSourceGate.allows(controllerIdentifier) else { return }
        action(self)
    }

    private func detach(_ controller: GCController?) {
        guard let gamepad = controller?.extendedGamepad else { return }
        gamepad.leftShoulder.pressedChangedHandler = nil
        gamepad.leftThumbstickButton?.pressedChangedHandler = nil
        gamepad.leftTrigger.pressedChangedHandler = nil
        gamepad.rightTrigger.pressedChangedHandler = nil
        gamepad.rightShoulder.pressedChangedHandler = nil
        gamepad.buttonA.pressedChangedHandler = nil
        gamepad.buttonX.pressedChangedHandler = nil
        gamepad.dpad.up.pressedChangedHandler = nil
        gamepad.dpad.down.pressedChangedHandler = nil
        gamepad.leftThumbstick.valueChangedHandler = nil
        gamepad.rightThumbstick.valueChangedHandler = nil
        gamepad.buttonB.pressedChangedHandler = nil
        gamepad.buttonY.pressedChangedHandler = nil
    }

    private func handleDpad(_ direction: SelectionDirection) {
        analogRepeatTask?.cancel()
        analogRepeatTask = nil
        if let stick = activeController?.extendedGamepad?.leftThumbstick {
            analogInterpreter.dpadDidMove(currentX: stick.xAxis.value, currentY: stick.yAxis.value)
        }
        onMove?(.directionalPad, direction)
    }

    private func handleAnalog(x: Float, y: Float) {
        let direction = analogInterpreter.update(
            x: x,
            y: y,
            at: ProcessInfo.processInfo.systemUptime
        )
        guard let direction else {
            if analogInterpreter.activeDirection == nil {
                analogRepeatTask?.cancel()
                analogRepeatTask = nil
            }
            return
        }
        onMove?(.leftStick, direction)
        startAnalogRepeat()
    }

    private func startAnalogRepeat() {
        analogRepeatTask?.cancel()
        analogRepeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, let self else { return }
                if let direction = analogInterpreter.repeatedMove(
                    at: ProcessInfo.processInfo.systemUptime
                ) {
                    onMove?(.leftStick, direction)
                }
                if analogInterpreter.activeDirection == nil { return }
            }
        }
    }

    private func handleScrollAnalog(x: Float, y: Float) {
        guard scrollingEnabled else { return }
        scrollInterpreter.update(x: x, y: y, configuration: scrollConfiguration)
        if scrollInterpreter.ratePointsPerSecond == 0 {
            cancelScrollTask()
        } else {
            startScrollTicksIfNeeded()
        }
    }

    private func startScrollTicksIfNeeded() {
        guard scrollTask == nil else { return }
        scrollTaskGeneration &+= 1
        let generation = scrollTaskGeneration
        scrollTask = Task { [weak self] in
            guard let self else { return }
            var previous = ProcessInfo.processInfo.systemUptime
            defer {
                if scrollTaskGeneration == generation { scrollTask = nil }
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, scrollingEnabled else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let delta = scrollInterpreter.delta(elapsed: now - previous)
                previous = now
                if delta != 0 { onSessionScroll?(delta) }
                if scrollInterpreter.ratePointsPerSecond == 0 { return }
            }
        }
    }

    private func stopSessionScrolling() {
        scrollingEnabled = false
        cancelScrollTask()
        scrollInterpreter.deactivate()
    }

    private func cancelScrollTask() {
        scrollTaskGeneration &+= 1
        scrollTask?.cancel()
        scrollTask = nil
    }
}
