import Foundation
import Testing
@testable import AgentControllerMac

@Test func codexModeShortcutUsesDocumentedMacDefaultWithoutAnOverride() throws {
    let shortcut = try CodexModeShortcutResolver(loadKeymap: { nil }).resolve()

    #expect(CodexModeShortcutResolver.contract.semanticAction == "activateCodexTaskMode")
    #expect(CodexModeShortcutResolver.contract.commandIdentifier == "switchToMode2")
    #expect(CodexModeShortcutResolver.contract.targetBundleIdentifier == "com.openai.codex")
    #expect(shortcut == .defaultCodexMode)
    #expect(shortcut.displayName == "Control+2")
}

@Test func codexModeShortcutFollowsTheCodexKeymapOverride() throws {
    let data = Data("""
    [
      {"command":"nextTab","key":"Ctrl+Tab"},
      {"command":"switchToMode2","key":"Command+9"}
    ]
    """.utf8)

    let shortcut = try CodexModeShortcutResolver(loadKeymap: { data }).resolve()

    #expect(shortcut.displayName == "Command+9")
    #expect(shortcut.triggerMode == .pulse)
}

@Test func codexModeShortcutTreatsAnExplicitNullAsDisabled() {
    let data = Data("""
    [{"command":"switchToMode2","key":null}]
    """.utf8)

    #expect(throws: CodexModeShortcutError.commandDisabled) {
        try CodexModeShortcutResolver(loadKeymap: { data }).resolve()
    }
}

@Test func codexModeShortcutRejectsAnUnsupportedCustomAccelerator() {
    let data = Data("""
    [{"command":"switchToMode2","key":"Control+F13"}]
    """.utf8)

    #expect(throws: CodexModeShortcutError.unsupportedShortcut) {
        try CodexModeShortcutResolver(loadKeymap: { data }).resolve()
    }
}

@Test func malformedCodexKeymapMatchesCodexFallbackBehavior() throws {
    let malformed = Data("not-json".utf8)

    let shortcut = try CodexModeShortcutResolver(loadKeymap: { malformed }).resolve()

    #expect(shortcut == .defaultCodexMode)
}
