import Darwin
import Foundation

public enum CodexDesktopStopResult: Equatable, Sendable {
    case interrupted(turnID: String)
    case idle
}

public enum CodexDesktopStopError: LocalizedError, Equatable, Sendable {
    case invalidThreadIdentifier
    case socketUnavailable
    case unsafeSocket
    case connectionFailed
    case timedOut
    case protocolMismatch
    case targetUnavailable
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidThreadIdentifier:
            "The managed Codex session identifier is invalid."
        case .socketUnavailable:
            "Codex Desktop's local control socket is unavailable."
        case .unsafeSocket:
            "Codex Desktop's local control socket failed its ownership check."
        case .connectionFailed:
            "Agent Controller could not connect to Codex Desktop."
        case .timedOut:
            "Codex Desktop did not answer the Stop request in time."
        case .protocolMismatch:
            "This Codex Desktop build does not support the tested Stop contract."
        case .targetUnavailable:
            "The managed Codex session is not open in Codex Desktop."
        case .invalidResponse:
            "Codex Desktop returned an unreadable Stop response."
        }
    }
}

public struct CodexDesktopStopAdapter: Sendable {
    static let interruptMethod = "thread-follower-interrupt-turn"
    static let interruptVersion = 2
    static let maximumFrameBytes = 1_048_576

    final class CancellationContext: @unchecked Sendable {
        private let lock = NSLock()
        private var descriptor: Int32?
        private var cancelled = false

        var isCancelled: Bool {
            lock.withLock { cancelled }
        }

        func register(_ descriptor: Int32) throws {
            let shouldCancel = lock.withLock { () -> Bool in
                guard !cancelled else { return true }
                self.descriptor = descriptor
                return false
            }
            if shouldCancel { throw CancellationError() }
        }

        func finish(_ descriptor: Int32) {
            lock.withLock {
                guard self.descriptor == descriptor else { return }
                self.descriptor = nil
                Darwin.close(descriptor)
            }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
                if let descriptor { Darwin.shutdown(descriptor, SHUT_RDWR) }
            }
        }

        func check() throws {
            if isCancelled { throw CancellationError() }
        }
    }

    private let exchange: @Sendable (
        _ threadID: String,
        _ cancellation: CancellationContext
    ) throws -> CodexDesktopStopResult

    public init(
        socketPath: String = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/ipc/ipc.sock").path,
        timeout: TimeInterval = 12
    ) {
        exchange = { threadID, cancellation in
            try Self.performStop(
                threadID: threadID,
                socketPath: socketPath,
                timeout: max(timeout, 0.1),
                cancellation: cancellation
            )
        }
    }

    init(
        socketPath: String = "/test/codex/ipc.sock",
        timeout: TimeInterval = 12,
        exchange: @escaping @Sendable (
            _ threadID: String,
            _ cancellation: CancellationContext
        ) throws -> CodexDesktopStopResult
    ) {
        self.exchange = exchange
    }

    public func stop(threadID: String) async throws -> CodexDesktopStopResult {
        guard CodexAppServerClient.isValidThreadID(threadID) else {
            throw CodexDesktopStopError.invalidThreadIdentifier
        }
        let cancellation = CancellationContext()
        let exchange = exchange
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try cancellation.check()
                        continuation.resume(returning: try exchange(threadID, cancellation))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    static func initializationRequest(requestID: String) -> [String: Any] {
        [
            "type": "request",
            "requestId": requestID,
            "sourceClientId": "initializing-client",
            "version": 0,
            "method": "initialize",
            "params": ["clientType": "agent-controller"],
        ]
    }

    static func interruptRequest(
        requestID: String,
        clientID: String,
        threadID: String
    ) -> [String: Any] {
        [
            "type": "request",
            "requestId": requestID,
            "sourceClientId": clientID,
            "version": interruptVersion,
            "method": interruptMethod,
            "params": ["conversationId": threadID],
            "timeoutMs": 5_000,
        ]
    }

    static func decodeInitializationResponse(
        _ message: [String: Any],
        requestID: String
    ) throws -> String {
        guard message["type"] as? String == "response",
              message["requestId"] as? String == requestID,
              message["resultType"] as? String == "success",
              message["method"] as? String == "initialize",
              let result = message["result"] as? [String: Any],
              let clientID = result["clientId"] as? String,
              UUID(uuidString: clientID) != nil else {
            throw CodexDesktopStopError.protocolMismatch
        }
        return clientID
    }

    static func decodeInterruptResponse(
        _ message: [String: Any],
        requestID: String
    ) throws -> CodexDesktopStopResult {
        guard message["type"] as? String == "response",
              message["requestId"] as? String == requestID else {
            throw CodexDesktopStopError.invalidResponse
        }
        if message["resultType"] as? String == "error" {
            switch message["error"] as? String {
            case "no-client-found": throw CodexDesktopStopError.targetUnavailable
            case "request-timeout": throw CodexDesktopStopError.timedOut
            default: throw CodexDesktopStopError.protocolMismatch
            }
        }
        guard message["resultType"] as? String == "success",
              message["method"] as? String == interruptMethod,
              let result = message["result"] as? [String: Any],
              result["ok"] as? Bool == true else {
            throw CodexDesktopStopError.protocolMismatch
        }
        if let turnID = result["interruptedTurnId"] as? String {
            guard CodexAppServerClient.isValidThreadID(turnID) else {
                throw CodexDesktopStopError.invalidResponse
            }
            return .interrupted(turnID: turnID)
        }
        guard result["interruptedTurnId"] is NSNull else {
            throw CodexDesktopStopError.invalidResponse
        }
        return .idle
    }
}
