import AgentControllerMac
import Foundation
import XCTest

final class CodexAppServerClientLiveTests: XCTestCase {
    func testRecentSessionCanBeListedAndRevalidated() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AGENT_CONTROLLER_LIVE_CODEX_SESSIONS"] == "1",
            "Set AGENT_CONTROLLER_LIVE_CODEX_SESSIONS=1 for local Codex app-server proof."
        )

        let client = CodexAppServerClient()
        let snapshot = try await client.recentSessions(limit: 3)
        let session = try XCTUnwrap(snapshot.sessions.first)
        let exists = try await client.sessionExists(session.id)
        XCTAssertTrue(exists)

        let inventory = try await client.recentInventory(sessionLimit: 3, projectLimit: 3)
        let project = try XCTUnwrap(inventory.projects.first)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
