import AgentControllerMac
import Foundation
import XCTest

final class CodexDesktopStopLiveTests: XCTestCase {
    func testDesktopIPCRejectsAnUnknownManagedSessionWithoutSideEffects() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AGENT_CONTROLLER_LIVE_CODEX_STOP_IPC"] == "1",
            "Set AGENT_CONTROLLER_LIVE_CODEX_STOP_IPC=1 for local Codex Desktop IPC proof."
        )

        do {
            _ = try await CodexDesktopStopAdapter().stop(
                threadID: "00000000-0000-7000-8000-000000000000"
            )
            XCTFail("An unknown session must not be accepted by Codex Desktop.")
        } catch CodexDesktopStopError.targetUnavailable {
            // Expected: framing, initialization, version negotiation, and discovery all succeeded.
        }
    }
}
