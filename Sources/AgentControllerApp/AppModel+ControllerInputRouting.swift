import AgentControllerCore
import Foundation

extension AppModel {
    func configureControllerInputRouting() {
        configurePrimaryInputRouting()
        configureNavigationInputRouting()
        configureStopMonitoring()
    }

    private func configurePrimaryInputRouting() {
        controllerMonitor.onHoldChanged = { [weak self] identifier, pressed in
            guard let self else { return }
            let eventID = self.beginInputMonitorEvent(
                input: .leftShoulder,
                gesture: pressed ? .pressed : .released,
                action: .sessionPicker,
                route: "Codex session service"
            )
            if pressed {
                self.beginHold(controllerIdentifier: identifier, monitorEventID: eventID)
            } else {
                self.releaseHold(controllerIdentifier: identifier, monitorEventID: eventID)
            }
        }
        controllerMonitor.onProjectHoldChanged = { [weak self] identifier, pressed in
            guard let self else { return }
            let eventID = self.beginInputMonitorEvent(
                input: .leftStickButton,
                gesture: pressed ? .pressed : .released,
                action: .projectStarter,
                route: "Codex project service"
            )
            if pressed {
                self.beginProjectHold(controllerIdentifier: identifier, monitorEventID: eventID)
            } else {
                self.releaseProjectHold(controllerIdentifier: identifier, monitorEventID: eventID)
            }
        }
        controllerMonitor.onCommandHoldChanged = { [weak self] identifier, pressed in
            guard let self else { return }
            let eventID = self.beginInputMonitorEvent(
                input: .leftTrigger,
                gesture: pressed ? .pressed : .released,
                action: .commandModifier,
                route: "Global keyboard"
            )
            self.handleCommandHoldChanged(
                controllerIdentifier: identifier,
                pressed: pressed,
                monitorEventID: eventID
            )
        }
        controllerMonitor.onTabPressed = { [weak self] identifier in
            guard let self else { return }
            let eventID = self.beginInputMonitorEvent(
                input: .rightTrigger,
                gesture: .pressed,
                action: .tab,
                route: "Global keyboard"
            )
            self.handleTabPressed(controllerIdentifier: identifier, monitorEventID: eventID)
        }
        controllerMonitor.onEnterPressed = { [weak self] identifier in
            guard let self else { return }
            let eventID = self.beginInputMonitorEvent(
                input: .buttonA,
                gesture: .pressed,
                action: .enter,
                route: "Global keyboard"
            )
            self.handleEnterPressed(controllerIdentifier: identifier, monitorEventID: eventID)
        }
        controllerMonitor.onDictationHoldChanged = { [weak self] identifier, pressed in
            guard let self else { return }
            let eventID = self.beginInputMonitorEvent(
                input: .rightShoulder,
                gesture: pressed ? .pressed : .released,
                action: .pushToTalk,
                route: "Codex keyboard"
            )
            self.handleDictationHoldChanged(
                controllerIdentifier: identifier,
                pressed: pressed,
                monitorEventID: eventID
            )
        }
    }

    private func configureNavigationInputRouting() {
        controllerMonitor.onSessionScroll = { [weak self] delta in
            guard let self else { return }
            self.handleMonitoredSessionScroll(delta: delta)
        }
        controllerMonitor.onMove = { [weak self] input, direction in
            guard let self else { return }
            let eventID = self.beginInputMonitorEvent(
                input: input,
                gesture: .moved,
                action: .selectorNavigation,
                route: self.selectorMode == .projectStarter ? "Session Starter" : "Session Picker"
            )
            self.moveSelection(direction, monitorEventID: eventID)
        }
        controllerMonitor.onCancel = { [weak self] in
            guard let self else { return }
            let eventID = self.beginInputMonitorEvent(
                input: .buttonB,
                gesture: .pressed,
                action: .cancel,
                route: "Controller"
            )
            self.handleCancelPressed(monitorEventID: eventID)
        }
        controllerMonitor.onShowConsole = { [weak self] in
            guard let self else { return }
            let eventID = self.beginInputMonitorEvent(
                input: .buttonY,
                gesture: .pressed,
                action: .showController,
                route: "Agent Controller"
            )
            self.handleShowControlCenter(monitorEventID: eventID)
        }
    }

    private func handleMonitoredSessionScroll(delta: Int32) {
        let now = ProcessInfo.processInfo.systemUptime
        let eventID: UUID?
        if now - lastScrollMonitorEventAt >= 0.5 {
            lastScrollMonitorEventAt = now
            eventID = beginInputMonitorEvent(
                input: .rightStick,
                gesture: .moved,
                action: .sessionScroll,
                route: "Codex window"
            )
        } else {
            eventID = nil
        }
        handleSessionScroll(delta: delta, monitorEventID: eventID)
    }
}
