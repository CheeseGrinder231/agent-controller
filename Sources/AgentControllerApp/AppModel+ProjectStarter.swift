import AgentControllerCore
import AgentControllerMac
import Foundation

extension AppModel {
    func beginProjectHold(controllerIdentifier: String, monitorEventID: UUID? = nil) {
        guard allows(.projectStarter) else {
            publishEvent("Finish the active controller command before opening the Session Starter.")
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
        selectorMode = .projectStarter
        selectorSessions = []
        selectorProjects = recentProjects
        let timestamp = ProcessInfo.processInfo.systemUptime
        let output = projectStateMachine.begin(
            at: timestamp,
            context: context,
            controllerIdentifier: controllerIdentifier,
            itemIDs: selectorProjects.map(\.id),
            isArmed: isArmed
        )
        handleProject(output, monitorEventID: monitorEventID)
        guard case .holding = projectStateMachine.phase else { return }
        finishInputMonitorEvent(
            monitorEventID,
            status: .routed,
            detail: "Hold recognized; waiting for project preview."
        )

        holdTask?.cancel()
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.handleProject(
                self.projectStateMachine.activatePreview(
                    at: timestamp + self.projectStateMachine.holdDuration
                ),
                monitorEventID: monitorEventID
            )
        }
    }

    func releaseProjectHold(controllerIdentifier: String, monitorEventID: UUID? = nil) {
        holdTask?.cancel()
        let output = projectStateMachine.release(
            currentContext: applicationMonitor.currentContext(),
            controllerIdentifier: controllerIdentifier
        )
        handleProject(output, monitorEventID: monitorEventID)
    }

    func handleProject(_ output: GestureOutput, monitorEventID: UUID? = nil) {
        switch output {
        case .none:
            finishInputMonitorEvent(monitorEventID, status: .blocked, detail: "No active selector.")
        case .showPreview:
            showProjectPreview(monitorEventID: monitorEventID)
        case .selectionChanged(let index):
            selectedIndex = index
            publishEvent("Codex project selected.")
            finishInputMonitorEvent(monitorEventID, status: .completed, detail: "Selection moved.")
        case .cancelled(let reason):
            hideSelector()
            if reason != .disarmed {
                publishEvent(projectGestureCancellationMessage(for: reason))
            }
            finishInputMonitorEvent(
                monitorEventID,
                status: .cancelled,
                detail: "Session Starter cancelled."
            )
        case .commitSelection(let path, let frozenContext):
            openNewSessionPage(
                path: path,
                frozenContext: frozenContext,
                monitorEventID: monitorEventID
            )
        }
    }

    private func showProjectPreview(monitorEventID: UUID?) {
        selectorVisible = true
        selectedIndex = nil
        controllerMonitor.setSelectorNavigationActive(!selectorProjects.isEmpty)
        publishEvent(selectorProjects.isEmpty
            ? "No recent Codex projects are available."
            : "Choose with D-pad or left stick, then release L3.")
        finishInputMonitorEvent(
            monitorEventID,
            status: selectorProjects.isEmpty ? .blocked : .completed,
            detail: selectorProjects.isEmpty ? "No recent projects." : "Session Starter opened."
        )
    }

    private func openNewSessionPage(
        path: String,
        frozenContext: ApplicationContext,
        monitorEventID: UUID?
    ) {
        guard let selectedProject = selectorProjects.first(where: { $0.path == path }) else {
            hideSelector()
            publishEvent("Blocked: that Codex project is no longer available.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Selected project is unavailable."
            )
            refreshSessions()
            return
        }
        hideSelector()
        publishEvent("Opening a new Codex session page…")
        finishInputMonitorEvent(monitorEventID, status: .routed, detail: "Opening selected project.")
        commitTask?.cancel()
        let token = commitGate.begin()
        commitTask = Task { [weak self] in
            await self?.performNewSessionOpen(
                project: selectedProject,
                frozenContext: frozenContext,
                token: token,
                monitorEventID: monitorEventID
            )
        }
    }

    private func performNewSessionOpen(
        project: CodexProjectSummary,
        frozenContext: ApplicationContext,
        token: UInt64,
        monitorEventID: UUID?
    ) async {
        defer {
            if commitGate.isCurrent(token) { commitTask = nil }
        }
        do {
            guard canCommit(token: token, frozenContext: frozenContext) else {
                finishInputMonitorEvent(
                    monitorEventID,
                    status: .cancelled,
                    detail: "Focus changed before starting."
                )
                return
            }
            let modeShortcut = try codexModeShortcutResolver.resolve()
            try keyboardPulseAdapter.pulse(
                modeShortcut,
                frozenContext: frozenContext,
                targetBundleIdentifier: CodexModeShortcutResolver.contract.targetBundleIdentifier
            )
            accessibilityAuthorized = true
            try await Task.sleep(for: .milliseconds(180))
            guard canCommit(token: token, frozenContext: frozenContext) else {
                publishEvent("Cancelled: Codex focus changed while switching modes.")
                finishInputMonitorEvent(
                    monitorEventID,
                    status: .cancelled,
                    detail: "Focus changed while switching to Codex mode."
                )
                return
            }
            try sessionOpener.openNewSession(projectPath: project.path)
            guard !Task.isCancelled, commitGate.isCurrent(token) else { return }
            managedStopSession = nil
            publishEvent("Opened Codex's new session page in the selected project.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .completed,
                detail: "New project session page requested."
            )
            refreshSessions()
        } catch {
            handleNewSessionOpenError(error, token: token, monitorEventID: monitorEventID)
        }
    }

    private func handleNewSessionOpenError(
        _ error: Error,
        token: UInt64,
        monitorEventID: UUID?
    ) {
        if error is CancellationError {
            finishInputMonitorEvent(
                monitorEventID,
                status: .cancelled,
                detail: "Session start cancelled."
            )
            return
        }
        guard commitGate.isCurrent(token) else { return }
        switch error {
        case CodexSessionClientError.projectUnavailable:
            publishEvent("Blocked: that Codex project folder is no longer available.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Selected project is unavailable."
            )
        case let pulseError as KeyboardChordPulseError:
            synchronizeGlobalCommandState()
            handlePulseError(
                pulseError,
                actionName: "Session Starter",
                monitorEventID: monitorEventID
            )
        case CodexModeShortcutError.commandDisabled:
            publishEvent("Blocked: Codex's mode-switch shortcut is disabled.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Codex mode-switch shortcut is disabled."
            )
        case CodexModeShortcutError.unsupportedShortcut:
            publishEvent("Blocked: Codex's mode-switch shortcut is not supported.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Codex mode-switch shortcut is unsupported."
            )
        default:
            publishEvent("Blocked: Codex did not open a new task page for that project.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .failed,
                detail: "New-session link was rejected."
            )
        }
        refreshSessions()
    }
}
