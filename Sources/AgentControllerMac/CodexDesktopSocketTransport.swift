import Darwin
import Foundation

extension CodexDesktopStopAdapter {
    static func performStop(
        threadID: String,
        socketPath: String,
        timeout: TimeInterval,
        cancellation: CancellationContext
    ) throws -> CodexDesktopStopResult {
        try validateSocket(at: socketPath)
        let descriptor = try connectSocket(at: socketPath, timeout: timeout)
        var registered = false
        defer {
            if registered {
                cancellation.finish(descriptor)
            } else {
                Darwin.close(descriptor)
            }
        }
        try cancellation.register(descriptor)
        registered = true
        do {
            try validatePeer(descriptor)
            let clientID = try initializeConnection(descriptor: descriptor)
            try cancellation.check()
            return try interrupt(
                threadID: threadID,
                clientID: clientID,
                descriptor: descriptor
            )
        } catch {
            if cancellation.isCancelled { throw CancellationError() }
            throw error
        }
    }

    static func configureSocket(_ descriptor: Int32, timeout: TimeInterval) throws {
        var noSigPipe: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw CodexDesktopStopError.connectionFailed
        }
        let seconds = floor(timeout)
        var value = timeval(
            tv_sec: Int(seconds),
            tv_usec: Int32((timeout - seconds) * 1_000_000)
        )
        let size = socklen_t(MemoryLayout<timeval>.size)
        guard setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &value, size) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &value, size) == 0 else {
            throw CodexDesktopStopError.connectionFailed
        }
    }

    static func writeFrame(_ message: [String: Any], to descriptor: Int32) throws {
        let payload: Data
        do {
            payload = try JSONSerialization.data(withJSONObject: message)
        } catch {
            throw CodexDesktopStopError.invalidResponse
        }
        guard !payload.isEmpty, payload.count <= maximumFrameBytes else {
            throw CodexDesktopStopError.invalidResponse
        }
        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        try frame.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                throw CodexDesktopStopError.connectionFailed
            }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard written > 0 else {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        throw CodexDesktopStopError.timedOut
                    }
                    throw CodexDesktopStopError.connectionFailed
                }
                offset += written
            }
        }
    }

    private static func initializeConnection(descriptor: Int32) throws -> String {
        let requestID = UUID().uuidString.lowercased()
        try writeFrame(initializationRequest(requestID: requestID), to: descriptor)
        let response = try readResponse(matching: requestID, from: descriptor)
        return try decodeInitializationResponse(response, requestID: requestID)
    }

    private static func interrupt(
        threadID: String,
        clientID: String,
        descriptor: Int32
    ) throws -> CodexDesktopStopResult {
        let requestID = UUID().uuidString.lowercased()
        try writeFrame(
            interruptRequest(
                requestID: requestID,
                clientID: clientID,
                threadID: threadID
            ),
            to: descriptor
        )
        let response = try readResponse(matching: requestID, from: descriptor)
        return try decodeInterruptResponse(response, requestID: requestID)
    }

    private static func validateSocket(at socketPath: String) throws {
        let directoryPath = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        let expectedUser = getuid()
        var directoryStatus = stat()
        guard lstat(directoryPath, &directoryStatus) == 0 else {
            throw CodexDesktopStopError.socketUnavailable
        }
        guard directoryStatus.st_uid == expectedUser,
              directoryStatus.st_mode & S_IFMT == S_IFDIR,
              directoryStatus.st_mode & 0o777 == 0o700 else {
            throw CodexDesktopStopError.unsafeSocket
        }

        var socketStatus = stat()
        guard lstat(socketPath, &socketStatus) == 0 else {
            throw CodexDesktopStopError.socketUnavailable
        }
        guard socketStatus.st_uid == expectedUser,
              socketStatus.st_mode & S_IFMT == S_IFSOCK,
              socketStatus.st_mode & 0o777 == 0o600 else {
            throw CodexDesktopStopError.unsafeSocket
        }
    }

    private static func connectSocket(
        at socketPath: String,
        timeout: TimeInterval
    ) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CodexDesktopStopError.connectionFailed }
        do {
            try configureSocket(descriptor, timeout: timeout)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bytes = Array(socketPath.utf8CString)
            guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                throw CodexDesktopStopError.connectionFailed
            }
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                destination.initializeMemory(as: UInt8.self, repeating: 0)
                destination.copyBytes(from: bytes.map(UInt8.init(bitPattern:)))
            }
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
            guard result == 0 else { throw CodexDesktopStopError.connectionFailed }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func validatePeer(_ descriptor: Int32) throws {
        var user = uid_t()
        var group = gid_t()
        guard getpeereid(descriptor, &user, &group) == 0,
              user == getuid() else {
            throw CodexDesktopStopError.unsafeSocket
        }
    }

    private static func readResponse(
        matching requestID: String,
        from descriptor: Int32
    ) throws -> [String: Any] {
        for _ in 0..<64 {
            let message = try readFrame(from: descriptor)
            if message["type"] as? String == "client-discovery-request" {
                guard let discoveryID = message["requestId"] as? String else {
                    throw CodexDesktopStopError.invalidResponse
                }
                try writeFrame(
                    [
                        "type": "client-discovery-response",
                        "requestId": discoveryID,
                        "response": ["canHandle": false],
                    ],
                    to: descriptor
                )
                continue
            }
            if message["type"] as? String == "broadcast" { continue }
            if message["type"] as? String == "response",
               message["requestId"] as? String == requestID {
                return message
            }
        }
        throw CodexDesktopStopError.invalidResponse
    }

    private static func readFrame(from descriptor: Int32) throws -> [String: Any] {
        let header = try readExactly(MemoryLayout<UInt32>.size, from: descriptor)
        let length = header.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: UInt32.self).littleEndian
        }
        guard length > 0, length <= maximumFrameBytes else {
            throw CodexDesktopStopError.invalidResponse
        }
        let payload = try readExactly(Int(length), from: descriptor)
        do {
            guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                throw CodexDesktopStopError.invalidResponse
            }
            return object
        } catch let error as CodexDesktopStopError {
            throw error
        } catch {
            throw CodexDesktopStopError.invalidResponse
        }
    }

    private static func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                throw CodexDesktopStopError.connectionFailed
            }
            var offset = 0
            while offset < count {
                let received = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
                guard received > 0 else {
                    if received == 0 { throw CodexDesktopStopError.connectionFailed }
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        throw CodexDesktopStopError.timedOut
                    }
                    if errno == EINTR { continue }
                    throw CodexDesktopStopError.connectionFailed
                }
                offset += received
            }
        }
        return data
    }
}
