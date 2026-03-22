import Foundation

@Observable
final class BackendManager {

    // MARK: - State

    enum State: Equatable {
        case starting
        case ready
        case error(String)
        case crashed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.starting, .starting), (.ready, .ready): return true
            case (.error(let a), .error(let b)), (.crashed(let a), .crashed(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Properties

    private(set) var state: State = .starting
    private(set) var port: UInt16 = 0
    let apiClient = APIClient()

    var isReady: Bool { state == .ready }

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    // MARK: - Lifecycle

    func start(dbPath: String? = nil) async {
        await MainActor.run { state = .starting }

        guard let binaryURL = Bundle.main.url(forResource: "expense-manager-backend", withExtension: nil) else {
            await MainActor.run { state = .error("Backend binary not found in app bundle") }
            return
        }

        do {
            let assignedPort = try findAvailablePort()
            await MainActor.run { port = assignedPort }

            let resolvedDbPath: String
            if let provided = dbPath, !provided.isEmpty {
                resolvedDbPath = (provided as NSString).expandingTildeInPath
            } else {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let dir = appSupport.appendingPathComponent("SlaveOfCapitalism")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                resolvedDbPath = dir.appendingPathComponent("expense.db").path
            }

            let proc = Process()
            proc.executableURL = binaryURL
            proc.arguments = ["--port", "\(assignedPort)", "--db-path", resolvedDbPath]

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            stdoutPipe = outPipe
            stderrPipe = errPipe

            proc.terminationHandler = { [weak self] p in
                guard let self else { return }
                let exitCode = p.terminationStatus
                let reason = p.terminationReason
                Task { @MainActor in
                    if self.state == .ready || self.state == .starting {
                        let msg = "Process exited with code \(exitCode) (reason: \(reason.rawValue))"
                        self.state = .crashed(msg)
                    }
                }
            }

            try proc.run()
            process = proc

            // Update apiClient baseURL
            let url = URL(string: "http://127.0.0.1:\(assignedPort)")!
            await MainActor.run { apiClient.baseURL = url }

            try await pollHealth()
            await MainActor.run { state = .ready }

        } catch let apiError as APIError {
            await MainActor.run { state = .error(apiError.localizedDescription) }
        } catch {
            await MainActor.run { state = .error(error.localizedDescription) }
        }
    }

    func stop() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        process = nil
    }

    func restart(dbPath: String? = nil) async {
        stop()
        // Brief pause to let the process clean up
        try? await Task.sleep(nanoseconds: 300_000_000)
        await start(dbPath: dbPath)
    }

    // MARK: - Port Discovery

    func findAvailablePort() throws -> UInt16 {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw APIError.serverError("Failed to create socket")
        }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            throw APIError.serverError("Failed to bind socket")
        }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &addrLen)
            }
        }

        guard nameResult == 0 else {
            throw APIError.serverError("Failed to get socket name")
        }

        return UInt16(bigEndian: boundAddr.sin_port)
    }

    // MARK: - Health Polling

    private func pollHealth() async throws {
        let maxAttempts = 30
        for attempt in 1...maxAttempts {
            do {
                let healthy = try await apiClient.healthCheck()
                if healthy { return }
            } catch {
                // Not ready yet
            }
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw APIError.serverError("Backend did not become healthy after \(maxAttempts) attempts")
    }
}
