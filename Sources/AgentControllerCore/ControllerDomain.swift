import Foundation

public struct ApplicationContext: Equatable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String
    public let displayName: String

    public init(processIdentifier: Int32, bundleIdentifier: String, displayName: String) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

public enum CodexSessionStatus: Equatable, Sendable {
    case active(needsAttention: Bool)
    case idle
    case notLoaded
    case error
}

public struct CodexSessionSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let project: String
    public let workingDirectory: String?
    public let updatedAt: Date
    public let status: CodexSessionStatus

    public init(
        id: String,
        title: String,
        project: String,
        workingDirectory: String? = nil,
        updatedAt: Date,
        status: CodexSessionStatus
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.workingDirectory = workingDirectory
        self.updatedAt = updatedAt
        self.status = status
    }
}

public struct CodexProjectSummary: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let lastUsedAt: Date

    public init(name: String, path: String, lastUsedAt: Date) {
        self.name = name
        self.path = path
        self.lastUsedAt = lastUsedAt
    }
}

public struct CodexInventorySnapshot: Equatable, Sendable {
    public let generation: UUID
    public let loadedAt: Date
    public let sessions: [CodexSessionSummary]
    public let projects: [CodexProjectSummary]

    public init(
        generation: UUID = UUID(),
        loadedAt: Date = Date(),
        sessions: [CodexSessionSummary],
        projects: [CodexProjectSummary]
    ) {
        self.generation = generation
        self.loadedAt = loadedAt
        self.sessions = sessions
        self.projects = projects
    }
}

public struct CodexSessionSnapshot: Equatable, Sendable {
    public let generation: UUID
    public let loadedAt: Date
    public let sessions: [CodexSessionSummary]

    public init(
        generation: UUID = UUID(),
        loadedAt: Date = Date(),
        sessions: [CodexSessionSummary]
    ) {
        self.generation = generation
        self.loadedAt = loadedAt
        self.sessions = sessions
    }
}

public enum ProfileRegistry {
    public static let codexBundleIdentifier = "com.openai.codex"

    public static func supports(_ context: ApplicationContext?) -> Bool {
        context?.bundleIdentifier == codexBundleIdentifier
    }
}
