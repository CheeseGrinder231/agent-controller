import AgentControllerCore
import Testing
@testable import AgentControllerMac

@MainActor
@Test func codexDictationContractIsSemanticAndExact() {
    let contract = CodexDictationShortcutAdapter.contract

    #expect(contract.semanticAction == "pushToTalk")
    #expect(contract.adapterIdentifier == "codex.composer.startDictation-shortcut")
    #expect(contract.targetBundleIdentifier == "com.openai.codex")
    #expect(contract.shortcutDescription == "Configurable; default Control+Shift+D")
}

@MainActor
@Test func shortcutDefaultsAndConfigurationAreCanonical() {
    #expect(CodexKeyboardShortcut.defaultDictation.displayName == "Control+Shift+D")
    #expect(CodexKeyboardShortcut(description: "ctrl + shift + d")?.displayName == "Control+Shift+D")
    #expect(CodexKeyboardShortcut(description: "Command+Option+V")?.displayName == "Option+Command+V")
    #expect(CodexKeyboardShortcut(description: "D") == nil)
    #expect(CodexKeyboardShortcut(description: "Control+Banana") == nil)
}

@MainActor
@Test func shortcutSettingsFailClosedForInvalidDraftsAndSavedValues() {
    let missing = CodexKeyboardShortcutSetting(saved: nil)
    let invalidSaved = CodexKeyboardShortcutSetting(saved: "D")
    let invalidDraft = CodexKeyboardShortcutSetting(draft: "Control+Banana")

    #expect(missing.draft == "Control+Shift+D")
    #expect(missing.shortcut == .defaultDictation)
    #expect(missing.canDispatch)
    #expect(invalidSaved.draft == "D")
    #expect(!invalidSaved.canDispatch)
    #expect(!invalidDraft.canDispatch)
}

@MainActor
@Test func adapterPostsOneKeyDownAndOneKeyUp() throws {
    let codex = dictationCodex()
    var events: [Bool] = []
    let adapter = CodexDictationShortcutAdapter(
        trustCheck: { true },
        permissionRequest: { true },
        currentContext: { codex },
        postKeyEvent: { _, keyDown in
            events.append(keyDown)
            return true
        }
    )

    try adapter.begin(frozenContext: codex)
    #expect(throws: VoiceInputAdapterError.releasePending) {
        try adapter.begin(frozenContext: codex)
    }
    #expect(adapter.isHolding)
    #expect(events == [true])

    #expect(adapter.end())
    #expect(adapter.end())
    #expect(!adapter.isHolding)
    #expect(events == [true, false])
}

@MainActor
@Test func adapterFailsClosedBeforePosting() {
    let codex = dictationCodex()
    var events: [Bool] = []
    let adapter = CodexDictationShortcutAdapter(
        trustCheck: { false },
        permissionRequest: { false },
        currentContext: { codex },
        postKeyEvent: { _, keyDown in
            events.append(keyDown)
            return true
        }
    )

    #expect(throws: VoiceInputAdapterError.accessibilityPermissionRequired) {
        try adapter.begin(frozenContext: codex)
    }
    #expect(events.isEmpty)
    #expect(!adapter.isHolding)
}

@MainActor
@Test func adapterRejectsFocusDriftAndStillReleasesAfterAStartedHold() throws {
    let codex = dictationCodex()
    let terminal = ApplicationContext(
        processIdentifier: 99,
        bundleIdentifier: "com.apple.Terminal",
        displayName: "Terminal"
    )
    var frontmost = codex
    var events: [(Int32, Bool)] = []
    let adapter = CodexDictationShortcutAdapter(
        trustCheck: { true },
        permissionRequest: { true },
        currentContext: { frontmost },
        postKeyEvent: { processIdentifier, keyDown in
            events.append((processIdentifier, keyDown))
            return true
        }
    )

    try adapter.begin(frozenContext: codex)
    frontmost = terminal
    #expect(adapter.end())
    #expect(events.map(\.0) == [42, 42])
    #expect(events.map(\.1) == [true, false])

    #expect(throws: VoiceInputAdapterError.focusChanged) {
        try adapter.begin(frozenContext: codex)
    }
    #expect(events.map(\.1) == [true, false])
}

@MainActor
@Test func adapterRejectsFocusDriftImmediatelyBeforePosting() {
    let codex = dictationCodex()
    let terminal = ApplicationContext(
        processIdentifier: 99,
        bundleIdentifier: "com.apple.Terminal",
        displayName: "Terminal"
    )
    var contextReads = 0
    var posted = false
    let adapter = CodexDictationShortcutAdapter(
        trustCheck: { true },
        permissionRequest: { true },
        currentContext: {
            defer { contextReads += 1 }
            return contextReads == 0 ? codex : terminal
        },
        postKeyEvent: { _, _ in
            posted = true
            return true
        }
    )

    #expect(throws: VoiceInputAdapterError.focusChanged) {
        try adapter.begin(frozenContext: codex)
    }
    #expect(contextReads == 2)
    #expect(!posted)
    #expect(!adapter.isHolding)
}

@MainActor
@Test func failedReleaseRemainsRetryable() throws {
    let codex = dictationCodex()
    var releaseAttempts = 0
    let adapter = CodexDictationShortcutAdapter(
        trustCheck: { true },
        permissionRequest: { true },
        currentContext: { codex },
        postKeyEvent: { _, keyDown in
            guard !keyDown else { return true }
            releaseAttempts += 1
            return releaseAttempts > 1
        }
    )

    try adapter.begin(frozenContext: codex)
    #expect(!adapter.end())
    #expect(adapter.isHolding)
    #expect(adapter.end())
    #expect(!adapter.isHolding)
    #expect(releaseAttempts == 2)
}

@MainActor
@Test func activeHoldFreezesItsConfiguredShortcutUntilRelease() throws {
    let codex = dictationCodex()
    var events: [(String, Bool)] = []
    let adapter = CodexDictationShortcutAdapter(
        trustCheck: { true },
        permissionRequest: { true },
        currentContext: { codex },
        postKeyEvent: { _, shortcut, keyDown in
            events.append((shortcut.displayName, keyDown))
            return true
        }
    )
    let configured = CodexKeyboardShortcut(description: "Control+Shift+V")!
    let replacement = CodexKeyboardShortcut(description: "Command+Shift+P")!

    #expect(adapter.updateShortcut(configured))
    try adapter.begin(frozenContext: codex)
    #expect(!adapter.updateShortcut(replacement))
    #expect(adapter.end())
    #expect(events.map(\.0) == ["Control+Shift+V", "Control+Shift+V"])
    #expect(events.map(\.1) == [true, false])
}

private func dictationCodex() -> ApplicationContext {
    ApplicationContext(
        processIdentifier: 42,
        bundleIdentifier: "com.openai.codex",
        displayName: "Codex"
    )
}
