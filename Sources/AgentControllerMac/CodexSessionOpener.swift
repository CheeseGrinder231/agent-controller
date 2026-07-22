import AppKit
import Foundation

@MainActor
public struct CodexSessionOpener {
    public init() {}

    public func open(threadID: String) throws {
        let url = try Self.deepLink(threadID: threadID)
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
}
