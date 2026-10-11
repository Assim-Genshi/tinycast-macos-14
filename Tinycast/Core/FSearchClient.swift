import Darwin
import Foundation

public enum FSearchError: Error, LocalizedError, Sendable {
    case socketPathTooLong
    case connectionFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case serverError(String)
    case daemonNotRunning
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .socketPathTooLong:
            return "FSearch socket path is too long."
        case .connectionFailed(let msg):
            return "Failed to connect to FSearch: \(msg)"
        case .writeFailed(let msg):
            return "Failed to send request to FSearch: \(msg)"
        case .readFailed(let msg):
            return "Failed to read response from FSearch: \(msg)"
        case .serverError(let msg):
            return "FSearch error: \(msg)"
        case .daemonNotRunning:
            return "FSearch daemon is not running."
        case .badResponse:
            return "Invalid response from FSearch daemon."
        }
    }
}

public struct FSearchHitRaw: Codable, Sendable {
    public let kind: String
    public let mtime: UInt32
    public let path: String
    public let score: Int
    public let size: UInt64
}

public struct FSearchResponse: Codable, Sendable {
    public let ok: Bool
    public let took_us: UInt64?
    public let hits: [FSearchHitRaw]?
    public let error: String?
    public let id: Int?
}

public struct FSearchStatus: Codable, Sendable {
    public let ok: Bool
    public let entries: Int?
    public let dirs: Int?
    public let overlay: Int?
    public let event_id: UInt64?
    public let index_bytes: Int?
    public let full_disk_access: Bool?
    public let owner: Bool?
    public let error: String?
}

/// Thread-safe client communicating with the `fsearch` daemon over a Unix Domain Socket.
/// Foundation + Darwin only so it compiles standalone in test harnesses.
public actor FSearchClient {
    private let socketPath: String
    private var fd: Int32 = -1
    private var readBuffer = Data()
    private var nextQueryID: Int = 1

    public init(socketPath: String? = nil) {
        if let socketPath {
            self.socketPath = socketPath
        } else {
            let home = NSHomeDirectory()
            self.socketPath = "\(home)/Library/Application Support/FSearch/fsearch.sock"
        }
    }

    deinit {
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    /// Check daemon status or ping to verify connection.
    public func status() async throws -> FSearchStatus {
        let req = try JSONSerialization.data(withJSONObject: ["op": "status"])
        let line = try sendLine(req)
        return try JSONDecoder().decode(FSearchStatus.self, from: line)
    }

    /// Execute a file search query.
    public func search(query: String, limit: Int = 50) async throws -> (items: [FileSearchItem], tookMicros: UInt64) {
        let queryID = nextQueryID
        nextQueryID += 1

        let payload: [String: Any] = [
            "id": queryID,
            "q": query,
            "limit": limit
        ]
        let reqData = try JSONSerialization.data(withJSONObject: payload)
        let line = try sendLine(reqData)

        let resp = try JSONDecoder().decode(FSearchResponse.self, from: line)
        if !resp.ok {
            throw FSearchError.serverError(resp.error ?? "Search failed")
        }

        let rawHits = resp.hits ?? []
        let items: [FileSearchItem] = rawHits.map { hit in
            let kind = FileItemKind(rawValue: hit.kind) ?? .file
            let mtime = Date(timeIntervalSince1970: TimeInterval(hit.mtime))
            return FileSearchItem(
                path: hit.path,
                kind: kind,
                size: hit.size,
                mtime: mtime,
                score: hit.score
            )
        }
        return (items, resp.took_us ?? 0)
    }

    /// Attempt to launch the daemon if not currently reachable.
    public func ensureDaemonRunning() async -> Bool {
        if (try? await status()) != nil {
            return true
        }
        // Attempt spawn
        if spawnDaemon() {
            // Give daemon up to 1.5 seconds to bind socket
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if (try? await status()) != nil {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Socket transport

    private func sendLine(_ data: Data) throws -> Data {
        try ensureConnected()

        var toSend = data
        toSend.append(0x0A) // '\n'

        var totalSent = 0
        let count = toSend.count
        while totalSent < count {
            let sent = toSend.withUnsafeBytes { rawPtr in
                let ptr = rawPtr.baseAddress!.advanced(by: totalSent)
                return Darwin.write(fd, ptr, count - totalSent)
            }
            if sent <= 0 {
                let err = String(cString: strerror(errno))
                closeSocket()
                throw FSearchError.writeFailed(err)
            }
            totalSent += sent
        }

        return try readLine()
    }

    private func readLine() throws -> Data {
        while true {
            if let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
                let lineData = readBuffer.subdata(in: 0..<newlineIndex)
                readBuffer.removeSubrange(0...newlineIndex)
                return lineData
            }

            var chunk = [UInt8](repeating: 0, count: 8192)
            let readCount = Darwin.read(fd, &chunk, chunk.count)
            if readCount > 0 {
                readBuffer.append(contentsOf: chunk.prefix(readCount))
            } else if readCount == 0 {
                closeSocket()
                throw FSearchError.readFailed("Connection closed by peer")
            } else {
                let err = String(cString: strerror(errno))
                closeSocket()
                throw FSearchError.readFailed(err)
            }
        }
    }

    private func ensureConnected() throws {
        if fd >= 0 { return }

        let newFd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard newFd >= 0 else {
            let err = String(cString: strerror(errno))
            throw FSearchError.connectionFailed("socket creation: \(err)")
        }

        // Avoid SIGPIPE on broken pipe
        var nosigpipe: Int32 = 1
        setsockopt(newFd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        // Timeouts
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(newFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(newFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(newFd)
            throw FSearchError.socketPathTooLong
        }

        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress!, buf.count)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(newFd, $0, addrLen)
            }
        }

        if connectRes != 0 {
            let err = String(cString: strerror(errno))
            Darwin.close(newFd)
            throw FSearchError.connectionFailed(err)
        }

        self.fd = newFd
        self.readBuffer.removeAll()
    }

    private func closeSocket() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        readBuffer.removeAll()
    }

    private func spawnDaemon() -> Bool {
        let home = NSHomeDirectory()
        let candidatePaths = [
            "\(home)/.local/bin/fsearch",
            "/usr/local/bin/fsearch",
            "/opt/homebrew/bin/fsearch",
            "/Users/assimgenshi/Documents/2.coding project/fsearch/target/release/fsearch"
        ]

        let fm = FileManager.default
        guard let exePath = candidatePaths.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exePath)
        process.arguments = ["serve"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
