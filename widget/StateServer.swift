import Foundation
import Network

/// Port of the Python state_server.py to Swift
/// Handles both Unix socket (for hooks) and HTTP (for widget polling)
actor StateServer {
    // Configuration
    private let socketPath: String
    private let httpPort: UInt16
    private let idleTimeoutSeconds: TimeInterval

    // State
    private var sessions: [String: SessionData] = [:]
    private var unixSocketListener: NWListener?
    private var httpListener: NWListener?
    private var isRunning = false

    struct SessionData: Codable {
        let session_id: String
        var state: String
        let tty: String
        let cwd: String
        let project: String
        var last_update: String
        let timestamp: Int
        var context_percentage: Double?
        var input_tokens: Int?
    }

    struct ServerResponse: Codable {
        let sessions: [SessionData]
        let server_time: String
    }

    init(
        socketPath: String = NSHomeDirectory() + "/.claude/widget/state.sock",
        httpPort: UInt16 = 19847,
        idleTimeoutSeconds: TimeInterval = 300
    ) {
        self.socketPath = socketPath
        self.httpPort = httpPort
        self.idleTimeoutSeconds = idleTimeoutSeconds
    }

    func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        // Ensure socket directory exists
        let socketDir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: socketDir, withIntermediateDirectories: true)

        // Remove old socket if exists
        if FileManager.default.fileExists(atPath: socketPath) {
            try FileManager.default.removeItem(atPath: socketPath)
        }

        // Start Unix socket listener for hooks
        try await startUnixSocketListener()

        // Start HTTP listener for widget
        try await startHttpListener()

        print("Claude Sessions State Server running...")
        print("Unix socket: \(socketPath)")
        print("HTTP server: http://127.0.0.1:\(httpPort)")
    }

    func stop() {
        isRunning = false
        unixSocketListener?.cancel()
        httpListener?.cancel()

        // Clean up socket file
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }

        print("State server stopped")
    }

    // MARK: - Unix Socket Server (for hooks)

    private func startUnixSocketListener() async throws {
        // NWListener doesn't directly support Unix domain sockets well,
        // so we use Darwin sockets directly
        try await startDarwinUnixSocket()
    }

    private func startDarwinUnixSocket() async throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "StateServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(fd)
            throw NSError(domain: "StateServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket: \(errno)"])
        }

        chmod(socketPath, 0o600)

        guard listen(fd, 10) == 0 else {
            close(fd)
            throw NSError(domain: "StateServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen on socket"])
        }

        print("Hook server listening on: \(socketPath)")

        // Accept connections in background
        Task.detached { [weak self] in
            await self?.acceptUnixConnections(fd: fd)
        }
    }

    private func acceptUnixConnections(fd: Int32) async {
        // Make socket non-blocking
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        while isRunning {
            var clientAddr = sockaddr_un()
            var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(fd, sockaddrPtr, &addrLen)
                }
            }

            if clientFd >= 0 {
                Task {
                    await self.handleUnixClient(fd: clientFd)
                }
            } else if errno == EWOULDBLOCK || errno == EAGAIN {
                // No connection ready, wait a bit
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            } else {
                break
            }
        }

        close(fd)
    }

    private func handleUnixClient(fd: Int32) async {
        defer { close(fd) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count)

        guard bytesRead > 0 else { return }

        let data = Data(buffer[0 ..< bytesRead])

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("Invalid JSON from hook")
            return
        }

        let sessionId = json["session_id"] as? String ?? "unknown"
        let eventType = json["event"] as? String ?? "unknown"

        if eventType == "end" {
            sessions.removeValue(forKey: sessionId)
            print("Session ended: \(sessionId)")
        } else {
            let cwd = json["cwd"] as? String ?? ""
            let project = (cwd as NSString).lastPathComponent

            // Parse context data if available
            let contextPercentage = json["context_percentage"] as? Double
            let inputTokens = json["input_tokens"] as? Int

            let session = SessionData(
                session_id: sessionId,
                state: eventType,
                tty: json["tty"] as? String ?? "",
                cwd: cwd,
                project: project,
                last_update: ISO8601DateFormatter().string(from: Date()),
                timestamp: json["timestamp"] as? Int ?? 0,
                context_percentage: contextPercentage,
                input_tokens: inputTokens
            )

            sessions[sessionId] = session
            if let pct = contextPercentage {
                print("Session \(sessionId): \(eventType) (context: \(Int(pct * 100))%)")
            } else {
                print("Session \(sessionId): \(eventType)")
            }
        }
    }

    // MARK: - HTTP Server (for widget)

    private func startHttpListener() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: httpPort)!)
        httpListener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleHttpConnection(connection)
            }
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("HTTP server listening on: http://127.0.0.1:\(self.httpPort)")
            case let .failed(error):
                print("HTTP server failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: .global())
    }

    private func handleHttpConnection(_ connection: NWConnection) async {
        connection.start(queue: .global())

        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, _, _ in
            Task {
                guard let self else { return }

                if let data, let request = String(data: data, encoding: .utf8) {
                    let response = await self.handleHttpRequest(request)
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                } else {
                    connection.cancel()
                }
            }
        }
    }

    private func handleHttpRequest(_ request: String) -> String {
        let requestLine = request.components(separatedBy: "\r\n").first ?? ""

        if requestLine.contains("GET /state") || requestLine.contains("GET / ") {
            // Check for idle sessions
            let now = Date()
            let formatter = ISO8601DateFormatter()

            for (sessionId, var session) in sessions {
                if let lastUpdate = formatter.date(from: session.last_update) {
                    if now.timeIntervalSince(lastUpdate) > idleTimeoutSeconds {
                        session.state = "idle"
                        sessions[sessionId] = session
                    }
                }
            }

            let response = ServerResponse(
                sessions: Array(sessions.values),
                server_time: formatter.string(from: now)
            )

            guard let jsonData = try? JSONEncoder().encode(response),
                  let jsonString = String(data: jsonData, encoding: .utf8)
            else {
                return "HTTP/1.1 500 Internal Server Error\r\n\r\n"
            }

            return """
            HTTP/1.1 200 OK\r
            Content-Type: application/json\r
            Access-Control-Allow-Origin: *\r
            Content-Length: \(jsonData.count)\r
            \r
            \(jsonString)
            """
        }

        // DELETE /sessions/{id} - Remove a session (for stale session cleanup)
        if requestLine.hasPrefix("DELETE /sessions/") {
            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else {
                return "HTTP/1.1 400 Bad Request\r\n\r\n"
            }
            let path = String(parts[1])
            let sessionId = String(path.dropFirst("/sessions/".count))

            if sessions.removeValue(forKey: sessionId) != nil {
                print("Session removed (stale): \(sessionId)")
            }

            return "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        }

        return "HTTP/1.1 404 Not Found\r\n\r\n"
    }
}
