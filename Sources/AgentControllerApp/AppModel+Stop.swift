import AgentControllerCore
import AgentControllerMac
import Foundation

extension AppModel {
    func configureStopMonitoring() {
        controllerMonitor.onStopInputObserved = { [weak self] in
            self?.recordStopInputObserved()
        }
        controllerMonitor.onStopPressed = { [weak self] identifier in
            guard let self else { return }
            let eventID = beginInputMonitorEvent(
                input: .buttonX,
                gesture: .pressed,
                action: .stop,
                route: "Codex adapter"
            )
            handleStopPressed(controllerIdentifier: identifier, monitorEventID: eventID)
        }
    }

    func recordStopInputObserved() {
        lastStopEvent = timestampedStopEvent("Physical X signal received; routing…")
    }

    func handleStopPressed(controllerIdentifier _: String, monitorEventID: UUID? = nil) {
        guard isArmed else {
            publishStopEvent("X ignored because controller commands are paused.")
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "Controller paused.")
            return
        }
        controllerMonitor.requireSessionScrollNeutral()
        guard let frozenContext = context, isCodexFrontmost else {
            publishStopEvent("X received, but Codex is not frontmost.")
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "Codex is not frontmost.")
            return
        }
        guard allows(.stop) else {
            publishStopEvent("X received, but another controller command is active.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Another controller command is active."
            )
            return
        }

        if let managedStopSession {
            stopManagedSession(
                managedStopSession,
                frozenContext: frozenContext,
                monitorEventID: monitorEventID
            )
        } else {
            stopFrontmostCodexTask(
                frozenContext: frozenContext,
                shortcutOverride: mappingSettings.codexStop,
                monitorEventID: monitorEventID
            )
        }
    }

    private func publishStopEvent(_ message: String) {
        lastStopEvent = timestampedStopEvent(message)
        publishEvent(message, safetyCritical: true)
    }

    private func timestampedStopEvent(_ message: String) -> String {
        "\(Date.now.formatted(date: .omitted, time: .standard)) · \(message)"
    }

    private func stopFrontmostCodexTask(
        frozenContext: ApplicationContext,
        shortcutOverride: KeyboardChord?,
        monitorEventID: UUID?
    ) {
        guard stopTask == nil else {
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "Stop is already running.")
            return
        }
        isStoppingCodex = true
        finishInputMonitorEvent(monitorEventID, status: .routed, detail: "Stop command routed to Codex.")
        publishStopEvent(shortcutOverride == nil
            ? "X received. Sending Codex's Escape Stop sequence…"
            : "X received. Sending the configured Codex Stop shortcut…")

        let keyboardPulseAdapter = keyboardPulseAdapter
        stopTask = Task { [weak self] in
            guard let self else { return }
            defer {
                stopTask = nil
                isStoppingCodex = false
                synchronizeGlobalCommandState()
                synchronizeScrollAvailability()
            }
            guard context == frozenContext else {
                publishStopEvent("X cancelled because Codex focus changed.")
                finishInputMonitorEvent(monitorEventID, status: .cancelled, detail: "Codex focus changed.")
                return
            }
            do {
                try await postFrontmostStop(
                    shortcutOverride: shortcutOverride,
                    frozenContext: frozenContext,
                    keyboardPulseAdapter: keyboardPulseAdapter
                )
                guard !Task.isCancelled else { return }
                accessibilityAuthorized = true
                publishStopEvent(shortcutOverride == nil
                    ? "X sent Codex's Escape Stop sequence."
                    : "X sent the configured Codex Stop shortcut.")
                finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Stop command posted.")
            } catch is CancellationError {
                finishInputMonitorEvent(monitorEventID, status: .cancelled, detail: "Stop command cancelled.")
            } catch {
                handlePulseError(error, actionName: "Codex Stop", monitorEventID: monitorEventID)
                publishStopEvent(lastEvent)
            }
        }
    }

    private func postFrontmostStop(
        shortcutOverride: KeyboardChord?,
        frozenContext: ApplicationContext,
        keyboardPulseAdapter: KeyboardChordPulseAdapter
    ) async throws {
        if let shortcutOverride {
            try keyboardPulseAdapter.pulse(
                shortcutOverride,
                frozenContext: frozenContext,
                targetBundleIdentifier: ProfileRegistry.codexBundleIdentifier
            )
        } else {
            try await keyboardPulseAdapter.pulseSequence(
                .defaultEscape,
                count: 3,
                interval: .milliseconds(120),
                frozenContext: frozenContext,
                targetBundleIdentifier: ProfileRegistry.codexBundleIdentifier
            )
        }
    }

    private func stopManagedSession(
        _ session: CodexSessionSummary,
        frozenContext: ApplicationContext,
        monitorEventID: UUID?
    ) {
        guard stopTask == nil else {
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "Stop is already running.")
            return
        }
        isStoppingCodex = true
        finishInputMonitorEvent(monitorEventID, status: .routed, detail: "Exact-session Stop routed.")
        publishStopEvent("X received. Stopping the exact session opened by LB…")
        let stopAdapter = stopAdapter
        stopTask = Task { [weak self] in
            guard let self else { return }
            defer {
                stopTask = nil
                isStoppingCodex = false
                synchronizeScrollAvailability()
            }
            guard context == frozenContext else {
                publishStopEvent("X cancelled because Codex focus changed.")
                finishInputMonitorEvent(monitorEventID, status: .cancelled, detail: "Codex focus changed.")
                return
            }
            await performManagedStop(
                session: session,
                stopAdapter: stopAdapter,
                monitorEventID: monitorEventID
            )
        }
    }

    private func performManagedStop(
        session: CodexSessionSummary,
        stopAdapter: CodexDesktopStopAdapter,
        monitorEventID: UUID?
    ) async {
        do {
            let result = try await stopAdapter.stop(threadID: session.id)
            guard !Task.isCancelled else { return }
            switch result {
            case .interrupted:
                publishStopEvent("X stopped the exact session opened by LB.")
                finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Exact session stopped.")
            case .idle:
                publishStopEvent("X target was already idle.")
                finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Exact session was idle.")
            }
            refreshSessions()
        } catch is CancellationError {
            finishInputMonitorEvent(monitorEventID, status: .cancelled, detail: "Stop command cancelled.")
        } catch CodexDesktopStopError.targetUnavailable {
            managedStopSession = nil
            publishStopEvent(managedStopFailureMessage("The managed session is no longer open in Codex."))
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "Managed session unavailable.")
        } catch CodexDesktopStopError.protocolMismatch {
            managedStopSession = nil
            publishStopEvent(managedStopFailureMessage("This Codex build changed its Stop contract."))
            finishInputMonitorEvent(monitorEventID, status: .failed, detail: "Stop contract changed.")
        } catch {
            managedStopSession = nil
            publishStopEvent(managedStopFailureMessage("Codex did not accept the managed Stop command."))
            finishInputMonitorEvent(monitorEventID, status: .failed, detail: "Codex rejected Stop.")
        }
    }

    private func managedStopFailureMessage(_ reason: String) -> String {
        if mappingSettings.codexStop != nil {
            return "\(reason) Press X again to use the recorded keyboard fallback."
        }
        return "\(reason) Press X again to stop the current frontmost task."
    }
}
