import AgentControllerCore
import AgentControllerMac
import Foundation

extension AppModel {
    func handleDictationHoldChanged(
        controllerIdentifier: String,
        pressed: Bool,
        monitorEventID: UUID? = nil
    ) {
        if pressed { controllerMonitor.requireSessionScrollNeutral() }
        guard !pressed || mappingSettings.codexDictation != nil else {
            publishEvent("Record an RB shortcut before dictating.", safetyCritical: true)
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "No Push to Talk mapping.")
            return
        }
        guard !pressed || allows(.dictation) else {
            publishEvent("Finish the active controller command before dictating.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Another controller command is active."
            )
            return
        }

        let output: VoiceHoldOutput
        if pressed {
            holdTask?.cancel()
            previewTask?.cancel()
            cancelPendingCommit()
            cancelGesture(.userCancelled)
            output = voiceStateMachine.begin(
                context: context,
                controllerIdentifier: controllerIdentifier,
                isArmed: isArmed
            )
        } else {
            output = voiceStateMachine.release(
                currentContext: applicationMonitor.currentContext(),
                controllerIdentifier: controllerIdentifier
            )
        }
        handleVoice(output, monitorEventID: monitorEventID)
    }

    func cancelVoice(_ reason: VoiceHoldCancellationReason) {
        let output = voiceStateMachine.cancel(reason)
        if output == .none, voiceAdapter.isHolding {
            finishVoiceRelease(
                successMessage: dictationCancellationMessage(for: reason),
                failureMessage: "RB release is still pending. Press B or disarm to retry."
            )
        } else {
            handleVoice(output)
        }
    }

    func handleVoice(_ output: VoiceHoldOutput, monitorEventID: UUID? = nil) {
        switch output {
        case .none:
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "No active voice hold.")
        case .beginDictation(let frozenContext):
            beginVoiceAdapter(frozenContext: frozenContext, monitorEventID: monitorEventID)
        case .endDictation:
            finishVoiceRelease(
                successMessage: "Dictation finished. Review the text in Codex before sending.",
                failureMessage: "RB release is still pending. Press B or disarm to retry.",
                monitorEventID: monitorEventID
            )
        case .cancelled(let reason, let shouldEndDictation):
            handleVoiceCancellation(
                reason: reason,
                shouldEndDictation: shouldEndDictation,
                monitorEventID: monitorEventID
            )
        }
    }

    func finishVoiceRelease(
        successMessage: String,
        failureMessage: String,
        monitorEventID: UUID? = nil,
        successStatus: InputMonitorStatus = .completed
    ) {
        let endedCleanly = endVoiceAdapter()
        isDictating = voiceAdapter.isHolding
        voiceReleasePending = !endedCleanly
        publishEvent(endedCleanly ? successMessage : failureMessage, safetyCritical: true)
        finishInputMonitorEvent(
            monitorEventID,
            status: endedCleanly ? successStatus : .failed,
            detail: endedCleanly ? "Push to Talk released." : "Key release is still pending."
        )
    }

    func endVoiceAdapter(maxAttempts: Int = 3) -> Bool {
        for _ in 0..<maxAttempts {
            if voiceAdapter.end() { return true }
        }
        return false
    }

    private func beginVoiceAdapter(
        frozenContext: ApplicationContext,
        monitorEventID: UUID?
    ) {
        do {
            try voiceAdapter.begin(frozenContext: frozenContext)
            accessibilityAuthorized = true
            isDictating = true
            voiceReleasePending = false
            publishEvent("Listening… release RB to finish dictation in Codex.", safetyCritical: true)
            finishInputMonitorEvent(
                monitorEventID,
                status: .completed,
                detail: "Push to Talk started."
            )
        } catch VoiceInputAdapterError.accessibilityPermissionRequired {
            _ = voiceStateMachine.cancel(.adapterBlocked)
            accessibilityAuthorized = false
            isDictating = false
            voiceReleasePending = false
            publishEvent(
                "RB dictation needs Accessibility permission. Session switching still works.",
                safetyCritical: true
            )
            finishInputMonitorEvent(
                monitorEventID,
                status: .failed,
                detail: "Accessibility permission required."
            )
        } catch {
            _ = voiceStateMachine.cancel(.adapterBlocked)
            finishVoiceRelease(
                successMessage: "RB dictation was blocked because the Codex adapter changed state.",
                failureMessage: "RB release is still pending. Press B or disarm to retry.",
                monitorEventID: monitorEventID,
                successStatus: .failed
            )
        }
    }

    private func handleVoiceCancellation(
        reason: VoiceHoldCancellationReason,
        shouldEndDictation: Bool,
        monitorEventID: UUID?
    ) {
        if shouldEndDictation {
            finishVoiceRelease(
                successMessage: dictationCancellationMessage(for: reason),
                failureMessage: "RB release is still pending. Press B or disarm to retry.",
                monitorEventID: monitorEventID,
                successStatus: .cancelled
            )
        } else if reason != .disarmed && reason != .adapterBlocked {
            publishEvent(dictationCancellationMessage(for: reason))
            finishInputMonitorEvent(
                monitorEventID,
                status: .cancelled,
                detail: "Push to Talk cancelled."
            )
        } else {
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Push to Talk was not active."
            )
        }
    }
}
