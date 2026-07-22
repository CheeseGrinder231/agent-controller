import AgentControllerCore
import Foundation

public enum CodexSessionClientError: LocalizedError, Equatable, Sendable {
    case cliUnavailable
    case appServerFailed
    case invalidResponse
    case sessionUnavailable
    case projectUnavailable
    case sessionStartRejected
    case invalidThreadIdentifier
    case deepLinkRejected

    public var errorDescription: String? {
        switch self {
        case .cliUnavailable:
            "Codex CLI is not installed in a supported location."
        case .appServerFailed:
            "Codex session service did not respond."
        case .invalidResponse:
            "Codex returned an unreadable session response."
        case .sessionUnavailable:
            "That Codex session is no longer available."
        case .projectUnavailable:
            "That Codex project folder is no longer available."
        case .sessionStartRejected:
            "Codex did not start a session for that project."
        case .invalidThreadIdentifier:
            "Codex returned an invalid session identifier."
        case .deepLinkRejected:
            "Codex did not accept the session link."
        }
    }
}

public struct CodexAppServerClient: Sendable {
    private let executableURL: URL?
    private let requestTimeout: TimeInterval
    private let maximumResponseBytes: Int

    public init(
        executableURL: URL? = nil,
        requestTimeout: TimeInterval = 8,
        maximumResponseBytes: Int = 2_000_000
    ) {
        self.executableURL = executableURL ?? Self.findCodexExecutable()
        self.requestTimeout = max(requestTimeout, 0.05)
        self.maximumResponseBytes = max(maximumResponseBytes, 1_024)
    }

    public func recentSessions(limit: Int = 10) async throws -> CodexSessionSnapshot {
        let safeLimit = min(max(limit, 1), 20)
        let response = try await request(.list(limit: max(safeLimit * 2, 12)))
        return CodexSessionSnapshot(
            sessions: try Self.decodeSessions(from: response, limit: safeLimit)
        )
    }

    public func recentInventory(
        sessionLimit: Int = 10,
        projectLimit: Int = 12
    ) async throws -> CodexInventorySnapshot {
        let safeSessionLimit = min(max(sessionLimit, 1), 20)
        let safeProjectLimit = min(max(projectLimit, 1), 20)
        let requestLimit = min(max(safeSessionLimit * 2, safeProjectLimit * 6, 60), 200)
        let response = try await request(.list(limit: requestLimit))
        let sessions = try Self.decodeSessions(from: response, limit: safeSessionLimit)
        let projects = try Self.decodeProjects(from: response, limit: safeProjectLimit)
            .filter { Self.isAvailableProjectDirectory($0.path) }
        return CodexInventorySnapshot(sessions: sessions, projects: projects)
    }

    public func startSession(in project: CodexProjectSummary) async throws -> CodexSessionSummary {
        guard let normalizedPath = Self.normalizedProjectPath(project.path),
              normalizedPath == project.path,
              Self.isAvailableProjectDirectory(normalizedPath) else {
            throw CodexSessionClientError.projectUnavailable
        }
        let response = try await request(.start(cwd: normalizedPath))
        do {
            return try Self.decodeStartedSession(from: response, expectedCwd: normalizedPath)
        } catch CodexSessionClientError.sessionUnavailable {
            throw CodexSessionClientError.sessionStartRejected
        }
    }

    public func sessionExists(_ threadID: String) async throws -> Bool {
        guard Self.isValidThreadID(threadID) else {
            throw CodexSessionClientError.invalidThreadIdentifier
        }
        let response = try await request(.read(threadID: threadID))
        return try Self.decodeThreadID(from: response) == threadID
    }

    private func request(_ request: CodexAppServerRequest) async throws -> Data {
        guard let executableURL else { throw CodexSessionClientError.cliUnavailable }
        let supervisor = CodexAppServerProcessSupervisor()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try CodexAppServerTransport.perform(
                    executableURL: executableURL,
                    request: request,
                    timeoutInterval: requestTimeout,
                    maximumResponseBytes: maximumResponseBytes,
                    supervisor: supervisor
                )
            }.value
        } onCancel: {
            supervisor.cancel()
        }
    }

    private static func findCodexExecutable() -> URL? {
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }
}
