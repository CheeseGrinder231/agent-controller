import AppKit
import Foundation

@MainActor
public struct CodexSessionOpener {
    public init() {}

    public func open(threadID: String) throws {
        let url = try Self.deepLink(threadID: threadID)
        try open(url)
    }

    public func openNewSession(projectPath: String) throws {
        let url = try Self.newSessionDeepLink(projectPath: projectPath)
        try open(url)
    }

    private func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw CodexSessionClientError.deepLinkRejected
        }
    }

    nonisolated static func deepLink(threadID: String) throws -> URL {
        guard CodexAppServerClient.isValidThreadID(threadID) else {
            throw CodexSessionClientError.invalidThreadIdentifier
        }
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(threadID)"
        guard let url = components.url else {
            throw CodexSessionClientError.invalidThreadIdentifier
        }
        return url
    }

    nonisolated static func newSessionDeepLink(projectPath: String) throws -> URL {
        guard let normalizedPath = CodexAppServerClient.normalizedProjectPath(projectPath),
              normalizedPath == projectPath,
              CodexAppServerClient.isAvailableProjectDirectory(normalizedPath) else {
            throw CodexSessionClientError.projectUnavailable
        }
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "path", value: normalizedPath)]
        guard let url = components.url else {
            throw CodexSessionClientError.projectUnavailable
        }
        return url
    }
}
