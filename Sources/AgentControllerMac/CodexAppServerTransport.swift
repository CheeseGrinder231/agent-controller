import Darwin
import Foundation

enum CodexAppServerRequest: Sendable {
    case list(limit: Int)
    case read(threadID: String)
    case start(cwd: String)

    var method: String {
        switch self {
        case .list: "thread/list"
        case .read: "thread/read"
        case .start: "thread/start"
        }
    }

    var params: [String: Any] {
        switch self {
        case .list(let limit):
            [
                "limit": limit,
                "sortKey": "recency_at",
                "sortDirection": "desc",
                "sourceKinds": ["cli", "vscode", "appServer"],
                "archived": false,
            ]
        case .read(let threadID):
            [
                "threadId": threadID,
                "includeTurns": false,
            ]
        case .start(let cwd):
            [
                "cwd": cwd,
                "ephemeral": false,
            ]
        }
    }
}

enum CodexAppServerTransport {
    static func perform(
        executableURL: URL,
        request: CodexAppServerRequest,
        timeoutInterval: TimeInterval,
        maximumResponseBytes: Int,
        supervisor: CodexAppServerProcessSupervisor
    ) throws -> Data {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        var didStart = false
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        defer {
            supervisor.detach(process)
            try? input.fileHandleForWriting.close()
            if didStart {
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
            }
        }

        do {
            try process.run()
            didStart = true
            guard supervisor.attach(process) else {
                throw CancellationError()
            }
            let timeout = DispatchWorkItem {
                supervisor.stop(.timedOut)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeoutInterval,
                execute: timeout
            )
            defer { timeout.cancel() }
            try send(request, to: input.fileHandleForWriting)
            let response = try responseLine(
                withID: 2,
                from: output.fileHandleForReading,
                maximumResponseBytes: maximumResponseBytes
            )
            switch supervisor.stopReason {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw CodexSessionClientError.appServerFailed
            case nil:
                break
            }
            return response
        } catch {
            switch supervisor.stopReason {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw CodexSessionClientError.appServerFailed
            case nil:
                break
            }
            if error is CancellationError {
                throw CancellationError()
            }
            if let clientError = error as? CodexSessionClientError {
                throw clientError
            }
            throw CodexSessionClientError.appServerFailed
        }
    }

    private static func send(_ request: CodexAppServerRequest, to handle: FileHandle) throws {
        try write(
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "agent_controller",
                        "title": "Agent Controller",
                        "version": "0.1.0",
                    ]
                ],
            ],
            to: handle
        )
        try write(["method": "initialized", "params": [:]], to: handle)
        try write(["method": request.method, "id": 2, "params": request.params], to: handle)
    }

    private static func write(_ message: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func responseLine(
        withID requestID: Int,
        from handle: FileHandle,
        maximumResponseBytes: Int
    ) throws -> Data {
        var buffer = Data()
        var receivedByteCount = 0
        while true {
            let chunk = handle.availableData
            guard !chunk.isEmpty else { break }
            receivedByteCount += chunk.count
            guard receivedByteCount <= maximumResponseBytes else {
                throw CodexSessionClientError.invalidResponse
            }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? NSNumber,
                      id.intValue == requestID else {
                    continue
                }
                return line
            }
        }
        throw CodexSessionClientError.invalidResponse
    }
}

final class CodexAppServerProcessSupervisor: @unchecked Sendable {
    enum StopReason: Equatable {
        case cancelled
        case timedOut
    }

    private let lock = NSLock()
    private var process: Process?
    private var reason: StopReason?

    var stopReason: StopReason? {
        lock.withLock { reason }
    }

    func attach(_ process: Process) -> Bool {
        lock.withLock {
            guard reason == nil else { return false }
            self.process = process
            return true
        }
    }

    func detach(_ process: Process) {
        lock.withLock {
            guard self.process === process else { return }
            self.process = nil
        }
    }

    func cancel() {
        stop(.cancelled)
    }

    func stop(_ newReason: StopReason) {
        let runningProcess = lock.withLock { () -> Process? in
            guard reason == nil else { return nil }
            reason = newReason
            return process
        }
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.forceStopIfNeeded()
            }
        }
    }

    private func forceStopIfNeeded() {
        let processIdentifier = lock.withLock { () -> Int32? in
            guard let process, process.isRunning else { return nil }
            return process.processIdentifier
        }
        if let processIdentifier {
            Darwin.kill(processIdentifier, SIGKILL)
        }
    }
}
