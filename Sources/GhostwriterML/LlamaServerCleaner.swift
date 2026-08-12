import Foundation
import GhostwriterCore

/// Cleanup brain: a Ghostwriter-managed local `llama-server` subprocess
/// (llama.cpp via Homebrew) running a small instruct model at temperature 0.
/// Fully local; the only network use is the one-time GGUF download, which
/// llama-server itself performs and caches (~/Library/Caches/llama.cpp).
public final class LlamaServerCleaner: TextCleaner {
    public static var defaultBinary: URL {
        let paths = [
            "/opt/homebrew/bin/llama-server",  // Apple Silicon
            "/usr/local/bin/llama-server"       // Intel
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: paths[0])  // Fallback to Apple Silicon
    }
    public static let defaultModelSpec = "unsloth/Qwen3-4B-Instruct-2507-GGUF:Q4_K_M"
    public static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ghostwriter/llama-server.log")

    private let serverBinary: URL
    private let modelSpec: String
    private let port: Int
    private var process: Process?
    private let session: URLSession

    public init(serverBinary: URL = LlamaServerCleaner.defaultBinary,
                modelSpec: String = LlamaServerCleaner.defaultModelSpec,
                port: Int = 8873) {
        self.serverBinary = serverBinary; self.modelSpec = modelSpec; self.port = port
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        session = URLSession(configuration: cfg)
    }

    public static func binaryExists() -> Bool {
        FileManager.default.isExecutableFile(atPath: defaultBinary.path)
    }
    public var isRunning: Bool { process?.isRunning ?? false }

    private var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// Starts llama-server if not already healthy. First run downloads the GGUF
    /// (~2.4 GB) — pass a generous readyTimeout then.
    public func ensureRunning(readyTimeout: TimeInterval = 90,
                              status: ((String) -> Void)? = nil) async throws {
        if await isHealthy() { return }
        if process?.isRunning != true {
            status?("Starting cleanup model…")
            let p = Process()
            p.executableURL = serverBinary
            p.arguments = ["-hf", modelSpec,
                           "--host", "127.0.0.1", "--port", "\(port)",
                           "-c", "4096", "-ngl", "99", "--no-webui"]
            try? FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
            let log = try? FileHandle(forWritingTo: Self.logURL)
            p.standardOutput = log; p.standardError = log
            try p.run()
            process = p
        }
        let deadline = Date().addingTimeInterval(readyTimeout)
        while Date() < deadline {
            if await isHealthy() { status?("Cleanup model ready."); return }
            if process?.isRunning != true {
                throw NSError(domain: "Ghostwriter", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "llama-server exited early — see \(Self.logURL.path)"])
            }
            status?("Waiting for cleanup model… (first run downloads ~2.4 GB)")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw NSError(domain: "Ghostwriter", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "llama-server not ready in \(Int(readyTimeout))s"])
    }

    private func isHealthy() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("health"))
        req.timeoutInterval = 2
        guard let (_, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return true
    }

    public func clean(transcript: String, systemPrompt: String) async throws -> String {
        try await ensureRunning()
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript],
            ],
            "temperature": 0,
            "max_tokens": 2048,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "Ghostwriter", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Bad llama-server response"])
        }
        return content
    }

    public func shutdown() { process?.terminate(); process = nil }
}
