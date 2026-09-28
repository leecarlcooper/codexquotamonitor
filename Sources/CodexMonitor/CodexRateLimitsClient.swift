import Foundation

/// Uses Codex's supported app-server protocol; credentials stay owned by Codex.
final class CodexRateLimitsClient {
    enum ClientError: LocalizedError {
        case unavailable, timeout, exited, invalidResponse, server

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Install Codex CLI and sign in with codex login, then refresh."
            case .timeout: return "Codex usage request timed out. Try Refresh."
            case .exited: return "Codex exited before returning usage. Update Codex CLI and try again."
            case .invalidResponse: return "Codex returned no supported usage windows. Update Codex CLI and try again."
            case .server: return "Codex could not read usage. Check your connection and ChatGPT sign-in with codex login."
            }
        }
    }

    struct Response: Decodable {
        let rateLimits: Bucket?
        let rateLimitsByLimitId: [String: Bucket]?

        var limits: (fiveHour: UsageLimit?, weekly: UsageLimit?)? {
            // Never substitute another model's bucket for the main Codex allowance.
            let bucket: Bucket?
            if let buckets = rateLimitsByLimitId, !buckets.isEmpty {
                bucket = buckets["codex"]
            } else {
                bucket = rateLimits.flatMap { $0.limitId == nil || $0.limitId == "codex" ? $0 : nil }
            }
            let windows = [bucket?.primary, bucket?.secondary].compactMap { $0 }
            let five = windows.first { $0.windowDurationMins == 300 }?.usageLimit
            let weekly = windows.first { $0.windowDurationMins == 10080 }?.usageLimit
            return five == nil && weekly == nil ? nil : (five, weekly)
        }
    }

    struct Bucket: Decodable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
    }

    struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Double?

        var usageLimit: UsageLimit? {
            guard usedPercent.isFinite, (0...100).contains(usedPercent) else { return nil }
            let reset = resetsAt.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0)) } ?? ""
            return UsageLimit(percent: Int(usedPercent.rounded()), metric: .used, resetText: reset)
        }
    }

    static var executableURL: URL? {
        let paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                     NSHomeDirectory() + "/.local/bin/codex",
                     NSHomeDirectory() + "/.npm-global/bin/codex",
                     "/Applications/Codex.app/Contents/Resources/codex"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var completion: ((Result<Response, Error>) -> Void)?
    private var timeoutWork: DispatchWorkItem?

    /// All state is confined to the main queue. Each poll has a bounded child lifetime.
    func fetch(executable: URL? = CodexRateLimitsClient.executableURL, timeout: TimeInterval = 30,
               completion: @escaping (Result<Response, Error>) -> Void) {
        precondition(Thread.isMainThread)
        cancel()
        guard let executable else {
            completion(.failure(ClientError.unavailable))
            return
        }
        self.completion = completion
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        self.process = process
        self.input = input
        self.output = output
        process.executableURL = executable
        process.arguments = ["app-server"]
        // Do not let the monitor's working directory select a project configuration.
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, self.process === process else { return }
                if data.isEmpty {
                    self.finish(.failure(ClientError.exited))
                } else {
                    self.receive(data)
                }
            }
        }
        do {
            try process.run()
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_quota_monitor", "version": "1.0"]]])
            let work = DispatchWorkItem { [weak self] in self?.finish(.failure(ClientError.timeout)) }
            timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        } catch {
            finish(.failure(ClientError.unavailable))
        }
    }

    func cancel() {
        precondition(Thread.isMainThread)
        completion = nil
        cleanup()
    }

    private func send(_ message: [String: Any]) {
        do {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input?.fileHandleForWriting.write(contentsOf: data)
        } catch {
            finish(.failure(ClientError.exited))
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 2_000_000 else { finish(.failure(ClientError.invalidResponse)); return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = message["id"] as? Int else { continue }
            if message["error"] != nil {
                finish(.failure(ClientError.server))
                return
            }
            if id == 1 {
                send(["method": "initialized"])
                send(["id": 2, "method": "account/rateLimits/read"])
            } else if id == 2 {
                do {
                    guard let result = message["result"] else { throw ClientError.invalidResponse }
                    let data = try JSONSerialization.data(withJSONObject: result)
                    let response = try JSONDecoder().decode(Response.self, from: data)
                    guard response.limits != nil else { throw ClientError.invalidResponse }
                    finish(.success(response))
                } catch {
                    finish(.failure(ClientError.invalidResponse))
                }
                return
            }
        }
    }

    private func finish(_ result: Result<Response, Error>) {
        let callback = completion
        completion = nil
        cleanup()
        callback?(result)
    }

    private func cleanup() {
        timeoutWork?.cancel()
        timeoutWork = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        input = nil
        output = nil
        buffer.removeAll()
    }
}
