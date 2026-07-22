import Foundation
import Testing
import AgentControllerCore
@testable import AgentControllerMac

@Test func sessionListDecodesRealHistoryShapeWithoutTurns() throws {
    let response = try #require(fixtureResponse.data(using: .utf8))
    let sessions = try CodexAppServerClient.decodeSessions(from: response, limit: 10)

    #expect(sessions.count == 2)
    #expect(sessions[0].id == "019f7e48-66f8-7192-8446-d4e2cf9ae0e6")
    #expect(sessions[0].title == "Controller session picker")
    #expect(sessions[0].project == "agent-controller")
    #expect(sessions[0].workingDirectory == "/tmp/agent-controller")
    #expect(sessions[1].title == "Preview fallback")
}

@Test func projectListUsesDistinctNormalizedRealWorkingDirectories() throws {
    let response = try #require(projectFixtureResponse.data(using: .utf8))
    let projects = try CodexAppServerClient.decodeProjects(from: response, limit: 10)

    #expect(projects.count == 2)
    #expect(projects[0].name == "agent-controller")
    #expect(projects[0].path == "/tmp/agent-controller")
    #expect(projects[0].lastUsedAt == Date(timeIntervalSince1970: 1_784_541_600))
    #expect(projects[1].path == "/tmp/other-project")
}

@Test func projectPathsMustBeAbsoluteNormalizedAndBelowRoot() {
    #expect(CodexAppServerClient.normalizedProjectPath(" /tmp/project/../agent-controller/ ") == "/tmp/agent-controller")
    #expect(CodexAppServerClient.normalizedProjectPath("relative/project") == nil)
    #expect(CodexAppServerClient.normalizedProjectPath("/") == nil)
    #expect(CodexAppServerClient.normalizedProjectPath("   ") == nil)
}

@Test func startedSessionRequiresTheExactRequestedProject() throws {
    let response = try #require(startFixtureResponse.data(using: .utf8))
    let session = try CodexAppServerClient.decodeStartedSession(
        from: response,
        expectedCwd: "/tmp"
    )

    #expect(session.id == "019f8f00-0000-7000-8000-000000000001")
    #expect(session.title == "Untitled Codex chat")
    #expect(session.project == "tmp")
    #expect(session.workingDirectory == "/tmp")
    #expect(throws: CodexSessionClientError.invalidResponse) {
        try CodexAppServerClient.decodeStartedSession(from: response, expectedCwd: "/tmp/other")
    }
}

@Test func threadStartSendsOnlyTheFrozenProjectPathAndPersistenceFlag() async throws {
    let params = CodexAppServerClient.startRequestParams(cwd: "/tmp")
    #expect(CodexAppServerClient.startRequestMethod == "thread/start")
    #expect(params.count == 2)
    #expect(params["cwd"] as? String == "/tmp")
    #expect(params["ephemeral"] as? Bool == false)

    let script = #"""
    #!/bin/sh
    IFS= read -r _ || exit 1
    IFS= read -r _ || exit 1
    IFS= read -r _ || exit 1
    printf '%s\n' '{"id":2,"result":{"cwd":"/tmp","thread":{"id":"019f8f00-0000-7000-8000-000000000001","preview":"","cwd":"/tmp","ephemeral":false,"updatedAt":1784541700,"status":{"type":"idle"}}}}'
    """#
    let executable = try makeFakeServer(script: script)
    defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
    let client = CodexAppServerClient(executableURL: executable, requestTimeout: 2)
    let project = CodexProjectSummary(name: "tmp", path: "/tmp", lastUsedAt: .now)

    let session = try await client.startSession(in: project)

    #expect(session.id == "019f8f00-0000-7000-8000-000000000001")
    #expect(session.workingDirectory == "/tmp")
}

@Test func titleFallbackNeverProducesAnEmptyRow() {
    #expect(CodexAppServerClient.displayTitle(name: "  Named chat  ", preview: "Preview") == "Named chat")
    #expect(CodexAppServerClient.displayTitle(name: nil, preview: "  Preview  ") == "Preview")
    #expect(CodexAppServerClient.displayTitle(name: "", preview: "  ") == "Untitled Codex chat")
}

@Test func optionalSessionMetadataDegradesWithoutDroppingTheSession() throws {
    let response = try #require(minimalFixtureResponse.data(using: .utf8))
    let sessions = try CodexAppServerClient.decodeSessions(from: response, limit: 10)

    #expect(sessions.count == 1)
    #expect(sessions[0].id == "thread_ABC-123")
    #expect(sessions[0].title == "Untitled Codex chat")
    #expect(sessions[0].project == "Local workspace")
    #expect(sessions[0].updatedAt == .distantPast)
    #expect(sessions[0].status == .notLoaded)
}

@Test func malformedRequiredSessionFieldsSurfaceSchemaDrift() throws {
    let response = try #require(malformedFixtureResponse.data(using: .utf8))

    #expect(throws: CodexSessionClientError.invalidResponse) {
        try CodexAppServerClient.decodeSessions(from: response, limit: 10)
    }
}

@Test func threadIdentifiersAreSafeOpaquePathComponents() {
    #expect(CodexAppServerClient.isValidThreadID("thread_ABC-123.~"))
    #expect(!CodexAppServerClient.isValidThreadID("thread/escape"))
    #expect(!CodexAppServerClient.isValidThreadID("thread?query"))
    #expect(!CodexAppServerClient.isValidThreadID("."))
    #expect(!CodexAppServerClient.isValidThreadID(".."))
    #expect(!CodexAppServerClient.isValidThreadID(""))
}

@Test func opaqueThreadIdentifierBuildsAnExactCodexDeepLink() throws {
    let url = try CodexSessionOpener.deepLink(threadID: "thread_ABC-123.~")

    #expect(url.absoluteString == "codex://threads/thread_ABC-123.~")
}

@Test func appServerRequestHasABoundedDeadline() async throws {
    let executable = try makeFakeServer(script: "#!/bin/sh\nexec /bin/sleep 10\n")
    defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
    let client = CodexAppServerClient(executableURL: executable, requestTimeout: 0.1)
    let start = ContinuousClock.now

    do {
        _ = try await client.recentSessions()
        Issue.record("Expected the fake server to time out")
    } catch let error as CodexSessionClientError {
        #expect(error == .appServerFailed)
    }

    #expect(ContinuousClock.now - start < .seconds(2))
}

@Test func deadlineForceStopsATermIgnoringAppServer() async throws {
    let executable = try makeFakeServer(script: "#!/bin/sh\ntrap '' TERM\nexec /bin/sleep 10\n")
    defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
    let client = CodexAppServerClient(executableURL: executable, requestTimeout: 0.1)
    let start = ContinuousClock.now

    do {
        _ = try await client.recentSessions()
        Issue.record("Expected the fake server to time out")
    } catch let error as CodexSessionClientError {
        #expect(error == .appServerFailed)
    }

    #expect(ContinuousClock.now - start < .seconds(2))
}

@Test func cancellingARequestTerminatesTheAppServerProcess() async throws {
    let executable = try makeFakeServer(script: "#!/bin/sh\nexec /bin/sleep 10\n")
    defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
    let client = CodexAppServerClient(executableURL: executable, requestTimeout: 5)
    let start = ContinuousClock.now
    let task = Task { try await client.recentSessions() }

    try await Task.sleep(for: .milliseconds(50))
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Expected the cancelled request to throw")
    } catch is CancellationError {
        // Expected.
    }

    #expect(ContinuousClock.now - start < .seconds(2))
}

@Test func appServerResponseSizeIsBounded() async throws {
    let script = #"""
    #!/bin/sh
    IFS= read -r _ || exit 1
    IFS= read -r _ || exit 1
    IFS= read -r _ || exit 1
    printf '{"id":2,"result":{"data":[{"id":"'
    i=0
    while [ "$i" -lt 2048 ]; do
      printf x
      i=$((i + 1))
    done
    printf '"}]}}\n'
    """#
    let executable = try makeFakeServer(script: script)
    defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
    let client = CodexAppServerClient(
        executableURL: executable,
        requestTimeout: 2,
        maximumResponseBytes: 1_024
    )

    do {
        _ = try await client.recentSessions()
        Issue.record("Expected the oversized response to be rejected")
    } catch let error as CodexSessionClientError {
        #expect(error == .invalidResponse)
    }
}

private func makeFakeServer(script: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-controller-fake-server-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let executable = directory.appendingPathComponent("codex")
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return executable
}

private let fixtureResponse = #"""
{
  "id": 2,
  "result": {
    "data": [
      {
        "id": "019f7e48-66f8-7192-8446-d4e2cf9ae0e6",
        "name": "Controller session picker",
        "preview": "Safe fixture preview",
        "cwd": "/tmp/agent-controller",
        "ephemeral": false,
        "parentThreadId": null,
        "recencyAt": 1784541600,
        "updatedAt": 1784541500,
        "status": {"type": "active", "activeFlags": []}
      },
      {
        "id": "019f7e48-66f8-7192-8446-d4e2cf9ae0e7",
        "name": null,
        "preview": "Preview fallback",
        "cwd": "/tmp/other-project",
        "ephemeral": false,
        "parentThreadId": null,
        "recencyAt": null,
        "updatedAt": 1784541400,
        "status": {"type": "notLoaded"}
      },
      {
        "id": "019f7e48-66f8-7192-8446-d4e2cf9ae0e8",
        "name": "Ephemeral",
        "preview": "Filtered",
        "cwd": "/tmp/ignored",
        "ephemeral": true,
        "parentThreadId": null,
        "recencyAt": null,
        "updatedAt": 1784541300,
        "status": {"type": "idle"}
      }
    ],
    "nextCursor": null
  }
}
"""#

private let minimalFixtureResponse = #"""
{
  "id": 2,
  "result": {
    "data": [
      {
        "id": "thread_ABC-123",
        "ephemeral": false
      }
    ]
  }
}
"""#

private let malformedFixtureResponse = #"""
{
  "id": 2,
  "result": {
    "data": [
      {
        "id": "thread_ABC-123"
      }
    ]
  }
}
"""#

private let projectFixtureResponse = #"""
{
  "id": 2,
  "result": {
    "data": [
      {
        "id": "019f7e48-66f8-7192-8446-d4e2cf9ae0e6",
        "cwd": "/tmp/agent-controller/",
        "ephemeral": false,
        "parentThreadId": null,
        "recencyAt": 1784541600
      },
      {
        "id": "019f7e48-66f8-7192-8446-d4e2cf9ae0e7",
        "cwd": "/tmp/agent-controller",
        "ephemeral": false,
        "parentThreadId": null,
        "recencyAt": 1784541500
      },
      {
        "id": "019f7e48-66f8-7192-8446-d4e2cf9ae0e8",
        "cwd": "/tmp/other-project",
        "ephemeral": false,
        "parentThreadId": null,
        "updatedAt": 1784541400
      },
      {
        "id": "019f7e48-66f8-7192-8446-d4e2cf9ae0e9",
        "cwd": "/tmp/sub-agent",
        "ephemeral": false,
        "parentThreadId": "019f7e48-66f8-7192-8446-d4e2cf9ae0e6"
      }
    ]
  }
}
"""#

private let startFixtureResponse = #"""
{
  "id": 2,
  "result": {
    "cwd": "/tmp",
    "thread": {
      "id": "019f8f00-0000-7000-8000-000000000001",
      "preview": "",
      "cwd": "/tmp",
      "ephemeral": false,
      "updatedAt": 1784541700,
      "status": {"type": "idle"}
    }
  }
}
"""#
