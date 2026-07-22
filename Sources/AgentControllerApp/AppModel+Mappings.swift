import AgentControllerCore
import AgentControllerMac

extension AppModel {
    var isRecordingBinding: Bool { chordRecorder.isRecording }

    func requestAccessibilityAuthorization() {
        _ = commandTabAdapter.requestAuthorization()
        refreshAccessibilityAuthorization()
        publishEvent(accessibilityAuthorized
            ? mappingSettings.codexDictation != nil
                ? "Global controls and Codex keyboard mappings are ready."
                : "Record a valid RB shortcut before dictating."
            : "Allow Agent Controller in Accessibility, then return here.")
    }

    func refreshAccessibilityAuthorization() {
        accessibilityAuthorized = commandTabAdapter.isAuthorized && voiceAdapter.isAuthorized
    }

    func beginMappingRecording(_ action: ControllerMappingAction) {
        guard isArmed == false || (!appLocalCommandActive && !isCommandModifierHeld) else {
            mappingError = "Finish the active controller command first."
            return
        }
        guard endGlobalCommand(maxAttempts: 5), endVoiceAdapter(maxAttempts: 5) else {
            mappingError = "A key release is still pending. Press B and try again."
            return
        }

        editingMapping = action
        stagedMappingChord = nil
        mappingError = nil
        controllerMonitor.requireSessionScrollNeutral()
        chordRecorder.begin(
            triggerMode: action.triggerMode,
            completion: { [weak self] chord in
                guard let self, editingMapping == action else { return }
                stagedMappingChord = chord
                publishEvent("Captured \(chord.displayName). Save to apply it.", safetyCritical: true)
            },
            cancellation: { [weak self] reason in
                guard let self else { return }
                editingMapping = nil
                stagedMappingChord = nil
                mappingError = mappingCancellationMessage(reason)
                publishEvent(mappingError ?? "Binding capture cancelled.", safetyCritical: true)
            }
        )
        publishEvent("Press one keyboard chord, then release every key.", safetyCritical: true)
    }

    func saveStagedMapping() {
        guard let action = editingMapping, let candidate = stagedMappingChord else { return }
        if let conflict = mappingSettings.conflictingAction(for: candidate, action: action) {
            mappingError = "Already used by \(conflict.displayName)."
            publishEvent(mappingError ?? "That binding is already used.", safetyCritical: true)
            return
        }
        if action == .codexDictation, !voiceAdapter.updateShortcut(candidate) {
            mappingError = "Release RB before changing Push to Talk."
            return
        }

        mappingSettings.set(candidate, for: action)
        mappingStore.save(mappingSettings)
        editingMapping = nil
        stagedMappingChord = nil
        mappingError = nil
        publishEvent("\(action.displayName) set to \(candidate.displayName).", safetyCritical: true)
    }

    func cancelMappingRecording() {
        if chordRecorder.isRecording { chordRecorder.cancel() }
        editingMapping = nil
        stagedMappingChord = nil
        mappingError = nil
    }

    func resetMapping(_ action: ControllerMappingAction) {
        guard !isRecordingBinding, !hasPendingKeyRelease else { return }
        let defaultChord: KeyboardChord?
        switch action {
        case .globalTab: defaultChord = .defaultTab
        case .globalEnter: defaultChord = .defaultReturn
        case .codexDictation: defaultChord = .defaultDictation
        case .codexStop: defaultChord = nil
        }
        if let defaultChord,
           let conflict = mappingSettings.conflictingAction(for: defaultChord, action: action) {
            editingMapping = action
            mappingError = "Default is already used by \(conflict.displayName)."
            publishEvent(
                mappingError ?? "The default binding conflicts with another mapping.",
                safetyCritical: true
            )
            return
        }
        if action == .codexDictation, let defaultChord {
            guard voiceAdapter.updateShortcut(defaultChord) else { return }
        }
        mappingSettings.set(defaultChord, for: action)
        mappingStore.save(mappingSettings)
        editingMapping = nil
        stagedMappingChord = nil
        mappingError = nil
        publishEvent("\(action.displayName) reset.", safetyCritical: true)
    }

    private func mappingCancellationMessage(
        _ reason: KeyboardChordRecorder.CancellationReason
    ) -> String {
        switch reason {
        case .user: "Binding capture cancelled."
        case .focusLost: "Binding capture cancelled when the window lost focus."
        case .timedOut: "Binding capture timed out."
        case .invalidKey: "That key cannot be recorded."
        case .multipleKeys: "Press one non-modifier key at a time."
        }
    }
}
