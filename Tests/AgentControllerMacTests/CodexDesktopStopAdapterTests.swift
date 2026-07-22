import Darwin
import Foundation
import Testing
@testable import AgentControllerMac

@Test func stopRequestsUseTheVersionedDesktopIPCContract() throws {
    let initialization = CodexDesktopStopAdapter.initializationRequest(requestID: "init")
    #expect(initialization["type"] as? String == "request")
    #expect(initialization["sourceClientId"] as? String == "initializing-client")
    #expect(initialization["version"] as? Int == 0)
    #expect(initialization["method"] as? String == "initialize")
    #expect((initialization["params"] as? [String: String])?["clientType"] == "agent-controller")

    let request = CodexDesktopStopAdapter.interruptRequest(
        requestID: "stop",
        clientID: "11111111-1111-1111-1111-111111111111",
        threadID: "019f7e48-66f8-7192-8446-d4e2cf9ae0e6"
    )
    #expect(request["method"] as? String == "thread-follower-interrupt-turn")
    #expect(request["version"] as? Int == 2)
    #expect(request["targetClientId"] == nil)
    #expect((request["params"] as? [String: String])?["conversationId"]
        == "019f7e48-66f8-7192-8446-d4e2cf9ae0e6")
}

@Test func stopResponsesDistinguishInterruptedIdleAndUnavailable() throws {
    let interrupted = try CodexDesktopStopAdapter.decodeInterruptResponse(
        [
            "type": "response",
            "requestId": "stop",
            "resultType": "success",
            "method": "thread-follower-interrupt-turn",
            "result": [
                "ok": true,
                "interruptedTurnId": "019f8000-1111-7222-8333-444444444444",
            ],
        ],
        requestID: "stop"
    )
    #expect(interrupted == .interrupted(turnID: "019f8000-1111-7222-8333-444444444444"))

    let idle = try CodexDesktopStopAdapter.decodeInterruptResponse(
        [
            "type": "response",
            "requestId": "stop",
            "resultType": "success",
            "method": "thread-follower-interrupt-turn",
            "result": ["ok": true, "interruptedTurnId": NSNull()],
        ],
        requestID: "stop"
    )
    #expect(idle == .idle)

    #expect(throws: CodexDesktopStopError.targetUnavailable) {
        try CodexDesktopStopAdapter.decodeInterruptResponse(
            [
                "type": "response",
                "requestId": "stop",
                "resultType": "error",
                "error": "no-client-found",
            ],
            requestID: "stop"
        )
    }
}

@Test func stopRejectsInvalidTargetsBeforeOpeningIPC() async {
    let adapter = CodexDesktopStopAdapter { _, _ in
        Issue.record("Invalid thread IDs must not reach the IPC exchange")
        return .idle
    }

    await #expect(throws: CodexDesktopStopError.invalidThreadIdentifier) {
        try await adapter.stop(threadID: "not/a/thread")
    }
}

@Test func stopReturnsTheTypedExchangeResult() async throws {
    let expected = "019f8000-1111-7222-8333-444444444444"
    let adapter = CodexDesktopStopAdapter { threadID, _ in
        #expect(threadID == "019f7e48-66f8-7192-8446-d4e2cf9ae0e6")
        return .interrupted(turnID: expected)
    }

    let result = try await adapter.stop(
        threadID: "019f7e48-66f8-7192-8446-d4e2cf9ae0e6"
    )
    #expect(result == .interrupted(turnID: expected))
}

@Test func stopCancellationReachesAnInFlightExchange() async {
    let started = AsyncStream<Void>.makeStream()
    let adapter = CodexDesktopStopAdapter { _, cancellation in
        started.continuation.yield()
        while !cancellation.isCancelled { usleep(1_000) }
        throw CancellationError()
    }
    let task = Task {
        try await adapter.stop(threadID: "019f7e48-66f8-7192-8446-d4e2cf9ae0e6")
    }

    var iterator = started.stream.makeAsyncIterator()
    #expect(await iterator.next() != nil)
    task.cancel()
    await #expect(throws: CancellationError.self) {
        try await task.value
    }
    started.continuation.finish()
}

@Test func closedDesktopSocketFailsWithoutSIGPIPE() throws {
    var descriptors = [Int32](repeating: -1, count: 2)
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
    defer {
        if descriptors[0] >= 0 { Darwin.close(descriptors[0]) }
        if descriptors[1] >= 0 { Darwin.close(descriptors[1]) }
    }

    try CodexDesktopStopAdapter.configureSocket(descriptors[0], timeout: 1)
    Darwin.close(descriptors[1])
    descriptors[1] = -1

    #expect(throws: CodexDesktopStopError.connectionFailed) {
        try CodexDesktopStopAdapter.writeFrame(["type": "test"], to: descriptors[0])
    }
}
