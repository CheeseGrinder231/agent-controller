import AgentControllerCore
import Foundation

extension AppModel {
    func beginHold(controllerIdentifier: String, monitorEventID: UUID? = nil) {
        guard allows(.sessionPicker) else {
            publishEvent("Finish the active controller command before opening the session picker.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Another controller command is active."
            )
            return
        }
        controllerMonitor.requireSessionScrollNeutral()
        cancelPendingCommit()
        previewTask?.cancel()
        isPreviewOnly = false
        selectorMode = .sessionPicker
        selectorSessions = recentSessions
        selectorProjects = []
        let timestamp = ProcessInfo.processInfo.systemUptime
        let output = stateMachine.begin(
            at: timestamp,
            context: context,
            controllerIdentifier: controllerIdentifier,
            itemIDs: selectorSessions.map(\.id),
            isArmed: isArmed
        )
        handle(output, monitorEventID: monitorEventID)
        guard case .holding = stateMachine.phase else { return }
        finishInputMonitorEvent(
            monitorEventID,
            status: .routed,
            detail: "Hold recognized; waiting for preview."
        )

        holdTask?.cancel()
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.handle(
                self.stateMachine.activatePreview(at: timestamp + self.stateMachine.holdDuration),
                monitorEventID: monitorEventID
            )
        }
    }

    func moveSelection(_ direction: SelectionDirection, monitorEventID: UUID? = nil) {
        switch selectorMode {
        case .sessionPicker:
            handle(stateMachine.move(direction), monitorEventID: monitorEventID)
        case .projectStarter:
            handleProject(projectStateMachine.move(direction), monitorEventID: monitorEventID)
        }
    }

    func releaseHold(controllerIdentifier: String, monitorEventID: UUID? = nil) {
        holdTask?.cancel()
        let output = stateMachine.release(
            currentContext: applicationMonitor.currentContext(),
            controllerIdentifier: controllerIdentifier
        )
        handle(output, monitorEventID: monitorEventID)
    }

    func cancelGesture(_ reason: GestureCancellationReason) {
        holdTask?.cancel()
        cancelPendingCommit()
        let sessionOutput = stateMachine.cancel(reason)
        let projectOutput = projectStateMachine.cancel(reason)
        handle(sessionOutput)
        handleProject(projectOutput)
    }

    func handle(_ output: GestureOutput, monitorEventID: UUID? = nil) {
        switch output {
        case .none:
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "No active selector.")
        case .showPreview:
            showSessionPreview(monitorEventID: monitorEventID)
        case .selectionChanged(let index):
            selectedIndex = index
            publishEvent("Exact Codex session selected.")
            finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Selection moved.")
        case .cancelled(let reason):
            hideSelector()
            if reason != .disarmed {
                publishEvent(gestureCancellationMessage(for: reason))
            }
            finishInputMonitorEvent(monitorEventID, status: .cancelled, detail: "Session Picker cancelled.")
        case .commitSelection(let threadID, let frozenContext):
            commitSession(threadID: threadID, frozenContext: frozenContext, monitorEventID: monitorEventID)
        }
    }

    func hideSelector() {
        controllerMonitor.setSelectorNavigationActive(false)
        selectorVisible = false
        selectedIndex = nil
        selectorSessions = []
        selectorProjects = []
        isPreviewOnly = false
    }

    func cancelPendingCommit() {
        commitTask?.cancel()
        commitTask = nil
        commitGate.invalidate()
    }

    private func showSessionPreview(monitorEventID: UUID?) {
        selectorVisible = true
        selectedIndex = nil
        controllerMonitor.setSelectorNavigationActive(!selectorSessions.isEmpty)
        publishEvent(selectorSessions.isEmpty
            ? "No recent Codex sessions are available."
            : "Choose with D-pad or left stick, then release LB.")
        finishInputMonitorEvent(
            monitorEventID,
            status: selectorSessions.isEmpty ? .blocked : .completed,
            detail: selectorSessions.isEmpty ? "No recent sessions." : "Session Picker opened."
        )
    }

    private func commitSession(
        threadID: String,
        frozenContext: ApplicationContext,
        monitorEventID: UUID?
    ) {
        let selectedSession = selectorSessions.first(where: { $0.id == threadID })
        hideSelector()
        publishEvent("Opening the selected Codex session…")
        finishInputMonitorEvent(monitorEventID, status: .routed, detail: "Opening selected session.")
        commitTask?.cancel()
        let token = commitGate.begin()
        commitTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if commitGate.isCurrent(token) { commitTask = nil }
            }
            do {
                guard canCommit(token: token, frozenContext: frozenContext) else {
                    recordCommitFocusCancellation(token: token, monitorEventID: monitorEventID)
                    return
                }
                guard try await sessionClient.sessionExists(threadID) else {
                    recordUnavailableCommit(token: token, monitorEventID: monitorEventID)
                    return
                }
                guard canCommit(token: token, frozenContext: frozenContext) else {
                    recordCommitFocusCancellation(token: token, monitorEventID: monitorEventID)
                    return
                }
                try sessionOpener.open(threadID: threadID)
                guard !Task.isCancelled, commitGate.isCurrent(token) else { return }
                managedStopSession = selectedSession
                publishEvent("Opened the selected Codex session.")
                finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Selected session opened.")
                refreshSessions()
            } catch is CancellationError {
                return
            } catch {
                guard commitGate.isCurrent(token) else { return }
                publishEvent("Blocked: the selected Codex session could not be opened.")
                finishInputMonitorEvent(
                    monitorEventID,
                    status: .failed,
                    detail: "Session adapter rejected the request."
                )
                refreshSessions()
            }
        }
    }

    func canCommit(token: UInt64, frozenContext: ApplicationContext) -> Bool {
        !Task.isCancelled
            && commitGate.isCurrent(token)
            && applicationMonitor.currentContext() == frozenContext
    }

    private func recordCommitFocusCancellation(token: UInt64, monitorEventID: UUID?) {
        guard commitGate.isCurrent(token) else { return }
        publishEvent(gestureCancellationMessage(for: .focusChanged))
        finishInputMonitorEvent(
            monitorEventID,
            status: .cancelled,
            detail: "Focus changed before opening."
        )
    }

    private func recordUnavailableCommit(token: UInt64, monitorEventID: UUID?) {
        guard !Task.isCancelled, commitGate.isCurrent(token) else { return }
        publishEvent("Blocked: that Codex session is no longer available.")
        finishInputMonitorEvent(
            monitorEventID,
            status: .blocked,
            detail: "Selected session is unavailable."
        )
        refreshSessions()
    }
}
