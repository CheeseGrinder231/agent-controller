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
            startSession(path: path, frozenContext: frozenContext, monitorEventID: monitorEventID)
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

    private func startSession(
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
        publishEvent("Starting a new Codex session…")
        finishInputMonitorEvent(monitorEventID, status: .routed, detail: "Starting selected project.")
        commitTask?.cancel()
        let token = commitGate.begin()
        commitTask = Task { [weak self] in
            await self?.performSessionStart(
                project: selectedProject,
                frozenContext: frozenContext,
                token: token,
                monitorEventID: monitorEventID
            )
        }
    }

    private func performSessionStart(
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
            let startedSession = try await sessionClient.startSession(in: project)
            guard canCommit(token: token, frozenContext: frozenContext) else {
                publishEvent("Session created, but Codex focus changed before it could open.")
                finishInputMonitorEvent(
                    monitorEventID,
                    status: .cancelled,
                    detail: "Session created; focus changed before opening."
                )
                refreshSessions()
                return
            }
            do {
                try sessionOpener.open(threadID: startedSession.id)
            } catch {
                guard commitGate.isCurrent(token) else { return }
                publishEvent("Session started, but Codex did not open its task link.")
                finishInputMonitorEvent(
                    monitorEventID,
                    status: .failed,
                    detail: "Session created; task link was rejected."
                )
                refreshSessions()
                return
            }
            guard !Task.isCancelled, commitGate.isCurrent(token) else { return }
            managedStopSession = startedSession
            publishEvent("Started a new Codex session in the selected project.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .completed,
                detail: "New project session opened."
            )
            refreshSessions()
        } catch is CancellationError {
            finishInputMonitorEvent(
                monitorEventID,
                status: .cancelled,
                detail: "Session start cancelled."
            )
        } catch CodexSessionClientError.projectUnavailable {
            guard commitGate.isCurrent(token) else { return }
            publishEvent("Blocked: that Codex project folder is no longer available.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .blocked,
                detail: "Selected project is unavailable."
            )
            refreshSessions()
        } catch {
            guard commitGate.isCurrent(token) else { return }
            publishEvent("Blocked: Codex could not start a session for that project.")
            finishInputMonitorEvent(
                monitorEventID,
                status: .failed,
                detail: "Session start adapter rejected the request."
            )
            refreshSessions()
        }
    }
}
