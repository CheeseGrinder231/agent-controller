import AgentControllerCore
import AgentControllerMac
import Foundation

extension AppModel {
    var hasPendingKeyRelease: Bool {
        voiceReleasePending || globalReleasePending || keyboardPulseAdapter.releasePending
    }

    func allows(_ intent: ControllerCommandIntent) -> Bool {
        ControllerCommandArbiter.allows(
            intent,
            activity: ControllerCommandActivity(
                appLocalCommandActive: appLocalCommandActive,
                commandModifierHeld: isCommandModifierHeld,
                releasePending: hasPendingKeyRelease,
                recordingBinding: isRecordingBinding
            )
        )
    }

    func handleCommandHoldChanged(
        controllerIdentifier _: String,
        pressed: Bool,
        monitorEventID: UUID? = nil
    ) {
        if !pressed {
            guard isCommandModifierHeld || globalReleasePending else {
                finishInputMonitorEvent(
                    monitorEventID,
                    status: .blocked,
                    detail: "Command modifier was not active."
                )
                return
            }
            finishGlobalRelease(
                successMessage: "Command released.",
                failureMessage: "Command release is still pending. Press B or pause to retry.",
                monitorEventID: monitorEventID
            )
            return
        }

        guard isArmed else {
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "Controller paused.")
            return
        }
        guard allows(.commandModifier) else {
            publishEvent("Finish the active controller command before holding LT.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Another controller command is active."
            )
            return
        }

        controllerMonitor.requireSessionScrollNeutral()
        do {
            try commandTabAdapter.beginCommand()
            synchronizeGlobalCommandState()
            accessibilityAuthorized = true
            publishEvent("Command held. Tap RT to cycle apps; release LT to commit.")
            finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Command key held.")
        } catch {
            handleGlobalCommandError(error, monitorEventID: monitorEventID)
        }
    }

    func handleTabPressed(controllerIdentifier _: String, monitorEventID: UUID? = nil) {
        guard isArmed else {
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "Controller paused.")
            return
        }
        guard allows(.tabPulse) else {
            publishEvent("Finish the active controller command before pressing RT.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Another controller command is active."
            )
            return
        }

        do {
            try keyboardPulseAdapter.pulseSystem(
                mappingSettings.globalTab,
                externalModifiers: isCommandModifierHeld ? [.command] : []
            )
            synchronizeGlobalCommandState()
            accessibilityAuthorized = true
            publishEvent(isCommandModifierHeld ? "Command + Tab." : "Tab pressed.")
            finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Keyboard event posted.")
        } catch {
            synchronizeGlobalCommandState()
            handlePulseError(error, actionName: "RT", monitorEventID: monitorEventID)
        }
    }

    func handleEnterPressed(controllerIdentifier _: String, monitorEventID: UUID? = nil) {
        guard isArmed else {
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "Controller paused.")
            return
        }
        guard allows(.enterPulse) else {
            publishEvent("Finish the active controller command before pressing A.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Another controller command is active."
            )
            return
        }

        do {
            try keyboardPulseAdapter.pulseSystem(
                mappingSettings.globalEnter,
                externalModifiers: isCommandModifierHeld ? [.command] : []
            )
            synchronizeGlobalCommandState()
            accessibilityAuthorized = true
            publishEvent(isCommandModifierHeld ? "Command + Enter." : "Enter pressed.")
            finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Keyboard event posted.")
        } catch {
            synchronizeGlobalCommandState()
            handlePulseError(error, actionName: "A", monitorEventID: monitorEventID)
        }
    }

    func handleShowControlCenter(monitorEventID: UUID? = nil) {
        guard allows(.showConsole) else {
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Another controller command is active."
            )
            return
        }
        showControlCenter()
        finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Control Center opened.")
    }

    func handleCancelPressed(monitorEventID: UUID? = nil) {
        controllerMonitor.requireSessionScrollNeutral()
        stopTask?.cancel()
        if isRecordingBinding {
            cancelMappingRecording()
            finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Binding capture cancelled.")
            return
        }
        cancelGesture(.userCancelled)
        cancelVoice(.userCancelled)
        _ = endGlobalCommand(maxAttempts: 5)
        let releasePending = hasPendingKeyRelease
        publishEvent(
            releasePending ? "A key release is still pending. Press B to retry." : "Cancelled.",
            safetyCritical: releasePending
        )
        finishInputMonitorEvent(
            monitorEventID,
            status: releasePending ? .failed : .completed,
            detail: releasePending ? "A key release is still pending." : "Active command cancelled."
        )
    }

    @discardableResult
    func endGlobalCommand(maxAttempts: Int = 3) -> Bool {
        for _ in 0..<maxAttempts {
            let pulseReleased = keyboardPulseAdapter.releaseAll()
            let commandReleased = commandTabAdapter.releaseAll()
            if pulseReleased && commandReleased { break }
        }
        synchronizeGlobalCommandState()
        return !globalReleasePending && !isCommandModifierHeld
    }

    private func finishGlobalRelease(
        successMessage: String,
        failureMessage: String,
        monitorEventID: UUID? = nil
    ) {
        let endedCleanly = endGlobalCommand()
        publishEvent(endedCleanly ? successMessage : failureMessage, safetyCritical: true)
        finishInputMonitorEvent(
            monitorEventID,
            status: endedCleanly ? .completed : .failed,
            detail: endedCleanly ? "Command key released." : "Key release is still pending."
        )
    }

    func synchronizeGlobalCommandState() {
        isCommandModifierHeld = commandTabAdapter.isHoldingCommand
        globalReleasePending = commandTabAdapter.releasePending || keyboardPulseAdapter.releasePending
    }

    private func handleGlobalCommandError(_ error: Error, monitorEventID: UUID? = nil) {
        synchronizeGlobalCommandState()
        switch error {
        case MacCommandTabError.accessibilityPermissionRequired:
            accessibilityAuthorized = false
            publishEvent(
                "Global Command + Tab needs Accessibility permission.",
                safetyCritical: true
            )
            finishInputMonitorEvent(
                monitorEventID,
                status: .failed,
                detail: "Accessibility permission required."
            )
        case MacCommandTabError.releasePending:
            publishEvent(
                "A global key release is pending. Press B or pause to retry.",
                safetyCritical: true
            )
            finishInputMonitorEvent(
                monitorEventID,
                status: .failed,
                detail: "A key release is still pending."
            )
        default:
            let message = globalReleasePending
                ? "A global key release is pending. Press B or pause to retry."
                : "The global keyboard command could not be sent."
            publishEvent(message, safetyCritical: true)
            finishInputMonitorEvent(monitorEventID, status: .failed, detail: "Keyboard adapter failed.")
        }
    }

    func handlePulseError(_ error: Error, actionName: String, monitorEventID: UUID? = nil) {
        switch error {
        case KeyboardChordPulseError.accessibilityPermissionRequired:
            accessibilityAuthorized = false
            publishEvent("\(actionName) needs Accessibility permission.", safetyCritical: true)
            finishInputMonitorEvent(
                monitorEventID,
                status: .failed,
                detail: "Accessibility permission required."
            )
        case KeyboardChordPulseError.releasePending:
            publishEvent(
                "A keyboard release is pending. Press B or pause to retry.",
                safetyCritical: true
            )
            finishInputMonitorEvent(
                monitorEventID,
                status: .failed,
                detail: "A key release is still pending."
            )
        case KeyboardChordPulseError.focusChanged,
             KeyboardChordPulseError.unsupportedApplication:
            publishEvent("\(actionName) was blocked because app focus changed.", safetyCritical: true)
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "App focus changed.")
        default:
            publishEvent(
                keyboardPulseAdapter.releasePending
                    ? "A keyboard release is pending. Press B or pause to retry."
                    : "\(actionName) could not be sent.",
                safetyCritical: true
            )
            finishInputMonitorEvent(monitorEventID, status: .failed, detail: "Keyboard adapter failed.")
        }
    }
}
