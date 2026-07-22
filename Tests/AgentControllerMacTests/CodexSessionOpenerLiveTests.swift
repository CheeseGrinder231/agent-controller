import AgentControllerMac
import Foundation
import XCTest

@MainActor
final class CodexSessionOpenerLiveTests: XCTestCase {
    func testDocumentedDeepLinkIsAccepted() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AGENT_CONTROLLER_LIVE_CODEX_FOCUS_THREAD_ID"] != nil,
            "Set AGENT_CONTROLLER_LIVE_CODEX_FOCUS_THREAD_ID for reversible deep-link proof."
        )
        let threadID = try XCTUnwrap(
            ProcessInfo.processInfo.environment["AGENT_CONTROLLER_LIVE_CODEX_FOCUS_THREAD_ID"]
        )
        try CodexSessionOpener().open(threadID: threadID)
    }

    func testNewSessionDeepLinkIsAccepted() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AGENT_CONTROLLER_LIVE_CODEX_NEW_SESSION_PROJECT"] != nil,
            "Set AGENT_CONTROLLER_LIVE_CODEX_NEW_SESSION_PROJECT for reversible new-session proof."
        )
        let projectPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["AGENT_CONTROLLER_LIVE_CODEX_NEW_SESSION_PROJECT"]
        )
        try CodexSessionOpener().openNewSession(projectPath: projectPath)
    }
}
