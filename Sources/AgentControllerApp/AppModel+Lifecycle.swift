import AgentControllerCore
import AppKit
import Foundation

extension AppModel {
    func start() {
        guard !started else { return }
        started = true

        applicationMonitor.onChange = { [weak self] in self?.handleContextChange($0) }
        controllerMonitor.onConnectionChanged = { [weak self] name in
            self?.controllerName = name
            self?.handleControllerConnectionChange(name)
        }
        configureControllerInputRouting()
        controllerMonitor.onDisconnectActive = { [weak self] in
            self?.handleActiveControllerDisconnect()
        }

        applicationMonitor.start()
        refreshAccessibilityAuthorization()
        controllerMonitor.start()
        refreshSessions()
    }

    func stop() {
        holdTask?.cancel()
        previewTask?.cancel()
        inventoryTask?.cancel()
        cancelPendingCommit()
        stopTask?.cancel()
        cancelVoice(.disarmed)
        cancelMappingRecording()
        _ = endVoiceAdapter(maxAttempts: 5)
        _ = endGlobalCommand(maxAttempts: 5)
        isDictating = voiceAdapter.isHolding
        applicationMonitor.stop()
        controllerMonitor.stop()
    }

    func refreshSessions() {
        guard inventoryTask == nil else { return }
        inventoryState = .loading
        projectInventoryState = .loading
        inventoryTask = Task { [weak self] in
            guard let self else { return }
            defer { inventoryTask = nil }
            do {
                let snapshot = try await sessionClient.recentInventory(
                    sessionLimit: 10,
                    projectLimit: 12
                )
                guard !Task.isCancelled else { return }
                recentSessions = snapshot.sessions
                recentProjects = snapshot.projects
                inventoryState = .ready(count: snapshot.sessions.count)
                projectInventoryState = .ready(count: snapshot.projects.count)
                populateVisiblePreviewIfNeeded(from: snapshot)
                publishEvent(snapshot.sessions.isEmpty && snapshot.projects.isEmpty
                    ? "No recent local Codex sessions or projects found."
                    : "Codex sessions and projects are ready.")
            } catch {
                guard !Task.isCancelled else { return }
                inventoryState = .unavailable
                projectInventoryState = .unavailable
                publishEvent("Codex session and project inventory is unavailable.")
            }
        }
    }

    func previewSelector() {
        showPreview(mode: .sessionPicker)
    }

    func previewProjectSelector() {
        showPreview(mode: .projectStarter)
    }

    func showControlCenter() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { window in
            window.title == "Agent Controller" && window.canBecomeMain
        })?.makeKeyAndOrderFront(nil)
    }

    private func populateVisiblePreviewIfNeeded(from snapshot: CodexInventorySnapshot) {
        guard isPreviewOnly, selectorVisible else { return }
        switch selectorMode {
        case .sessionPicker where selectorSessions.isEmpty:
            selectorSessions = snapshot.sessions
            selectedIndex = selectorSessions.isEmpty ? nil : 0
        case .projectStarter where selectorProjects.isEmpty:
            selectorProjects = snapshot.projects
            selectedIndex = selectorProjects.isEmpty ? nil : 0
        default:
            break
        }
    }

    private func showPreview(mode: CodexSelectorMode) {
        cancelPendingCommit()
        previewTask?.cancel()
        isPreviewOnly = true
        selectorMode = mode
        switch mode {
        case .sessionPicker:
            selectorSessions = recentSessions
            selectorProjects = []
            selectedIndex = selectorSessions.isEmpty ? nil : 0
            publishEvent("Session picker preview. No session will open.")
            if recentSessions.isEmpty { refreshSessions() }
        case .projectStarter:
            selectorSessions = []
            selectorProjects = recentProjects
            selectedIndex = selectorProjects.isEmpty ? nil : 0
            publishEvent("Session Starter preview. No session will start.")
            if recentProjects.isEmpty { refreshSessions() }
        }
        selectorVisible = true
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.hideSelector()
        }
    }

    private func handleContextChange(_ newContext: ApplicationContext?) {
        controllerMonitor.requireSessionScrollNeutral()
        if context != newContext {
            cancelPendingCommit()
            stopTask?.cancel()
        }
        context = newContext
        handle(stateMachine.cancelIfContextChanged(to: newContext))
        handleProject(projectStateMachine.cancelIfContextChanged(to: newContext))

        let voiceOutput = voiceStateMachine.cancelIfContextChanged(to: newContext)
        if voiceOutput == .none, voiceAdapter.isHolding {
            finishVoiceRelease(
                successMessage: dictationCancellationMessage(for: .focusChanged),
                failureMessage: "RB release is still pending. Press B or disarm to retry."
            )
        } else {
            handleVoice(voiceOutput)
        }
        refreshAccessibilityAuthorization()
        if ProfileRegistry.supports(newContext) { refreshSessions() }
        synchronizeScrollAvailability()
    }
}
