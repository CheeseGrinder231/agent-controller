import AgentControllerCore
import Foundation

extension CodexAppServerClient {
    static func decodeSessions(from response: Data, limit: Int) throws -> [CodexSessionSummary] {
        let threads = try threadObjects(from: response)
        var sessions: [CodexSessionSummary] = []
        for thread in threads {
            guard let id = thread["id"] as? String,
                  let ephemeral = thread["ephemeral"] as? Bool,
                  isValidThreadID(id) else {
                throw CodexSessionClientError.invalidResponse
            }
            guard !ephemeral,
                  thread["parentThreadId"] == nil || thread["parentThreadId"] is NSNull else {
                continue
            }

            let cwd = thread["cwd"] as? String ?? ""
            sessions.append(CodexSessionSummary(
                id: id,
                title: displayTitle(
                    name: thread["name"] as? String,
                    preview: thread["preview"] as? String ?? ""
                ),
                project: projectName(for: cwd),
                workingDirectory: normalizedProjectPath(cwd),
                updatedAt: threadDate(thread) ?? .distantPast,
                status: sessionStatus(thread["status"] as? [String: Any] ?? [:])
            ))
            if sessions.count == limit { break }
        }
        return sessions
    }

    static func decodeProjects(from response: Data, limit: Int) throws -> [CodexProjectSummary] {
        let threads = try threadObjects(from: response)
        var seenPaths: Set<String> = []
        var projects: [CodexProjectSummary] = []
        for thread in threads {
            guard let ephemeral = thread["ephemeral"] as? Bool,
                  !ephemeral,
                  thread["parentThreadId"] == nil || thread["parentThreadId"] is NSNull,
                  let cwd = thread["cwd"] as? String,
                  let path = normalizedProjectPath(cwd),
                  seenPaths.insert(path).inserted else {
                continue
            }
            projects.append(CodexProjectSummary(
                name: projectName(for: path),
                path: path,
                lastUsedAt: threadDate(thread) ?? .distantPast
            ))
            if projects.count == limit { break }
        }
        return projects
    }

    static func decodeStartedSession(
        from response: Data,
        expectedCwd: String
    ) throws -> CodexSessionSummary {
        let result = try resultObject(from: response)
        guard let responseCwd = result["cwd"] as? String,
              normalizedProjectPath(responseCwd) == expectedCwd,
              let thread = result["thread"] as? [String: Any],
              let threadID = thread["id"] as? String,
              let ephemeral = thread["ephemeral"] as? Bool,
              !ephemeral,
              isValidThreadID(threadID),
              let threadCwd = thread["cwd"] as? String,
              normalizedProjectPath(threadCwd) == expectedCwd else {
            throw CodexSessionClientError.invalidResponse
        }
        return CodexSessionSummary(
            id: threadID,
            title: displayTitle(
                name: thread["name"] as? String,
                preview: thread["preview"] as? String ?? ""
            ),
            project: projectName(for: expectedCwd),
            workingDirectory: expectedCwd,
            updatedAt: threadDate(thread) ?? Date(),
            status: sessionStatus(thread["status"] as? [String: Any] ?? [:])
        )
    }

    static func decodeThreadID(from response: Data) throws -> String {
        let result = try resultObject(from: response)
        guard let thread = result["thread"] as? [String: Any],
              let id = thread["id"] as? String,
              let ephemeral = thread["ephemeral"] as? Bool,
              isValidThreadID(id),
              !ephemeral else {
            throw CodexSessionClientError.sessionUnavailable
        }
        return id
    }

    static func displayTitle(name: String?, preview: String) -> String {
        if let name = trimmedNonempty(name) { return name }
        if let preview = trimmedNonempty(preview) { return preview }
        return "Untitled Codex chat"
    }

    static func projectName(for cwd: String) -> String {
        guard !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Local workspace"
        }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Local workspace" : name
    }

    static func normalizedProjectPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, NSString(string: trimmed).isAbsolutePath else { return nil }
        let normalized = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
        return normalized == "/" ? nil : normalized
    }

    static func startRequestParams(cwd: String) -> [String: Any] {
        CodexAppServerRequest.start(cwd: cwd).params
    }

    static var startRequestMethod: String {
        CodexAppServerRequest.start(cwd: "/").method
    }

    static func isAvailableProjectDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static func isValidThreadID(_ threadID: String) -> Bool {
        guard !threadID.isEmpty,
              threadID != ".",
              threadID != "..",
              threadID.utf8.count <= 128 else { return false }
        return threadID.utf8.allSatisfy { byte in
            switch byte {
            case 45, 46, 48...57, 65...90, 95, 97...122, 126: true
            default: false
            }
        }
    }

    private static func threadObjects(from response: Data) throws -> [[String: Any]] {
        let result = try resultObject(from: response)
        guard let data = result["data"] as? [[String: Any]] else {
            throw CodexSessionClientError.invalidResponse
        }
        return data
    }

    private static func threadDate(_ thread: [String: Any]) -> Date? {
        let timestamp = (thread["recencyAt"] as? NSNumber)
            ?? (thread["updatedAt"] as? NSNumber)
            ?? (thread["createdAt"] as? NSNumber)
        return timestamp.map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    private static func trimmedNonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sessionStatus(_ status: [String: Any]) -> CodexSessionStatus {
        switch status["type"] as? String {
        case "active":
            .active(needsAttention: !((status["activeFlags"] as? [String]) ?? []).isEmpty)
        case "idle": .idle
        case "systemError": .error
        default: .notLoaded
        }
    }

    private static func resultObject(from response: Data) throws -> [String: Any] {
        do {
            guard let envelope = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  envelope["error"] == nil,
                  let result = envelope["result"] as? [String: Any] else {
                throw CodexSessionClientError.sessionUnavailable
            }
            return result
        } catch let error as CodexSessionClientError {
            throw error
        } catch {
            throw CodexSessionClientError.invalidResponse
        }
    }
}
