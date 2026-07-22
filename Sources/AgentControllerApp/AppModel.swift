import AgentControllerCore
import AgentControllerMac
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var controllerName: String?
    @Published var context: ApplicationContext?
    @Published var recentSessions: [CodexSessionSummary] = []
    @Published var recentProjects: [CodexProjectSummary] = []
    @Published var managedStopSession: CodexSessionSummary?
    @Published var selectorSessions: [CodexSessionSummary] = []
    @Published var selectorProjects: [CodexProjectSummary] = []
    @Published var inventoryState: SessionInventoryState = .idle
    @Published var projectInventoryState: SessionInventoryState = .idle
    @Published var selectorVisible = false
    @Published var selectorMode: CodexSelectorMode = .sessionPicker
    @Published var selectedIndex: Int?
    @Published var accessibilityAuthorized = false
    @Published var mappingSettings: ControllerMappingSettings
    @Published var editingMapping: ControllerMappingAction?
    @Published var stagedMappingChord: KeyboardChord?
    @Published var mappingError: String?
    @Published var isDictating = false
    @Published var isStoppingCodex = false
    @Published var voiceReleasePending = false
    @Published var isCommandModifierHeld = false
    @Published var globalReleasePending = false
    @Published var lastEvent = "Controller paused. No commands will run."
    @Published var lastStopEvent = "Not attempted."
    @Published var inputMonitorEvents: [InputMonitorEvent] = []
    @Published var isPreviewOnly = false
    @Published var isArmed = false {
        didSet {
            reconnectPolicy.userChangedEnablement(isArmed)
            guard oldValue != isArmed else { return }
            if isArmed {
                publishEvent(recentSessions.isEmpty && recentProjects.isEmpty
                    ? "Controller enabled. Waiting for Codex sessions and projects."
                    : "Controller enabled. Codex mappings are ready.")
            } else {
                cancelPendingCommit()
                stopTask?.cancel()
                _ = stateMachine.cancel(.disarmed)
                _ = projectStateMachine.cancel(.disarmed)
                cancelVoice(.disarmed)
                cancelMappingRecording()
                _ = endGlobalCommand(maxAttempts: 5)
                hideSelector()
                let releasePending = voiceReleasePending || globalReleasePending
                publishEvent(
                    releasePending
                        ? "Disarmed. A key release is still pending; press B to retry."
                        : "Controller paused. No commands will run.",
                    safetyCritical: releasePending
                )
            }
            synchronizeScrollAvailability()
        }
    }

    var isCodexFrontmost: Bool { ProfileRegistry.supports(context) }

    let controllerMonitor = ControllerMonitor()
    let applicationMonitor = FrontmostApplicationMonitor()
    let sessionClient = CodexAppServerClient()
    let sessionOpener = CodexSessionOpener()
    let voiceAdapter = CodexDictationShortcutAdapter()
    let keyboardPulseAdapter = KeyboardChordPulseAdapter()
    let codexModeShortcutResolver = CodexModeShortcutResolver()
    let scrollAdapter = CodexScrollAdapter()
    let stopAdapter = CodexDesktopStopAdapter()
    let mappingStore: ControllerMappingStore
    let chordRecorder = KeyboardChordRecorder()
    let commandTabAdapter = MacCommandTabAdapter()

    var stateMachine = HoldSelectionStateMachine()
    var projectStateMachine = HoldSelectionStateMachine()
    var voiceStateMachine = VoiceHoldStateMachine()
    var holdTask: Task<Void, Never>?
    var previewTask: Task<Void, Never>?
    var inventoryTask: Task<Void, Never>?
    var commitTask: Task<Void, Never>?
    var stopTask: Task<Void, Never>?
    var commitGate = SessionCommitGate()
    var reconnectPolicy = ControllerReconnectPolicy()
    var inputMonitorBuffer = InputMonitorBuffer()
    var lastScrollMonitorEventAt: TimeInterval = 0
    var started = false

    private init() {
        let mappingStore = ControllerMappingStore()
        self.mappingStore = mappingStore
        let settings = mappingStore.load()
        mappingSettings = settings
        if let shortcut = settings.codexDictation {
            _ = voiceAdapter.updateShortcut(shortcut)
        }
    }

    func publishEvent(_ message: String, safetyCritical: Bool = false) {
        synchronizeScrollAvailability()
        guard safetyCritical || !hasPendingKeyRelease else { return }
        lastEvent = message
    }

    var appLocalCommandActive: Bool {
        stateMachine.phase != .idle
            || projectStateMachine.phase != .idle
            || voiceStateMachine.phase != .idle
            || voiceAdapter.isHolding
            || selectorVisible
            || commitTask != nil
            || isStoppingCodex
    }
}
