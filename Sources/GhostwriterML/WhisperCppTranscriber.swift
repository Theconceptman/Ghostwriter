import Foundation
import GhostwriterCore

/// Intel transcription engine: a Ghostwriter-managed local `whisper-server`
/// subprocess (whisper.cpp via Homebrew) running the ggml small.en model.
/// WhisperKit's CoreML pipeline traps on x86_64 (EXC_BAD_ACCESS in
/// TextDecoding.prepareDecoderInputs, crash report verified 2026-08-12), so on
/// Intel the engine runs out of process: an engine crash can never take the
/// app down. Same lifecycle pattern as LlamaServerCleaner. Fully local; the
/// only network use is the one-time ggml model download.
public final class WhisperCppTranscriber: Transcriber {
    public static var defaultBinary: URL {
        let paths = [
            "/usr/local/bin/whisper-server",   // Intel (the slice that uses this engine)
            "/opt/homebrew/bin/whisper-server" // Apple Silicon (dev convenience)
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: paths[0])
    }
    /// Canonical ggml weights from the whisper.cpp author's Hugging Face repo.
    /// small.en: the accuracy/speed balance for 2015-2020 Intel CPUs. Checksum
    /// pinning is tracked in the decision record; the size gate below rejects
    /// truncated downloads.
    public static let defaultModelURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!
    public static let modelDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ghostwriter/models")
    public static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ghostwriter/whisper-server.log")
    /// small.en is about 466 MB; anything under this is a truncated download.
    private static let minModelBytes: UInt64 = 400_000_000

    public let modelName: String
    private let serverBinary: URL
    private let remoteModelURL: URL
    private let modelFile: URL
    private let port: Int
    private var process: Process?
    private let session: URLSession

    public init(serverBinary: URL = WhisperCppTranscriber.defaultBinary,
                modelURL: URL = WhisperCppTranscriber.defaultModelURL,
                port: Int = 8874) {
        self.serverBinary = serverBinary
        self.remoteModelURL = modelURL
        self.modelName = modelURL.lastPathComponent
        self.modelFile = Self.modelDir.appendingPathComponent(modelURL.lastPathComponent)
        self.port = port
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120   // CPU inference on Intel takes seconds, not ms
        cfg.timeoutIntervalForResource = 3600 // one-time model download
        session = URLSession(configuration: cfg)
    }

    public static func binaryExists() -> Bool {
        FileManager.default.isExecutableFile(atPath: defaultBinary.path)
    }
    public var isRunning: Bool { process?.isRunning ?? false }
    public var isLoaded: Bool { isRunning }
    public func unload() { shutdown() }

    private var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// Downloads the ggml model on first run, then starts whisper-server and
    /// waits until it answers. Mirrors WhisperTranscriber.preload so per-slice
    /// call sites compile unchanged.
    public func preload(status: ((String) -> Void)? = nil) async throws {
        try await ensureModel(status: status)
        try await ensureRunning(readyTimeout: 300, status: status)
    }

    private func ensureModel(status: ((String) -> Void)? = nil) async throws {
        let fm = FileManager.default
        if let size = try? fm.attributesOfItem(atPath: modelFile.path)[.size] as? UInt64,
           size >= Self.minModelBytes { return }
        try? fm.removeItem(at: modelFile) // clear truncated leftovers
        try fm.createDirectory(at: Self.modelDir, withIntermediateDirectories: true)
        status?("Downloading speech model \(modelName) (one-time, ~0.5 GB)…")
        let (tmp, resp) = try await session.download(from: remoteModelURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "Ghostwriter", code: 6, userInfo: [NSLocalizedDescriptionKey:
                "Speech model download failed: check the connection, then retry."])
        }
        let size = (try? fm.attributesOfItem(atPath: tmp.path)[.size] as? UInt64) ?? 0
        guard size >= Self.minModelBytes else {
            throw NSError(domain: "Ghostwriter", code: 6, userInfo: [NSLocalizedDescriptionKey:
                "Speech model download incomplete (\(size) bytes): retry."])
        }
        try? fm.removeItem(at: modelFile)
        try fm.moveItem(at: tmp, to: modelFile)
        status?("Speech model downloaded.")
    }

    /// Starts whisper-server if not already answering. First start loads the
    /// model from disk, which takes seconds on Intel hardware.
    public func ensureRunning(readyTimeout: TimeInterval = 90,
                              status: ((String) -> Void)? = nil) async throws {
        if await isListening() { return }
        try await ensureModel(status: status)
        if process?.isRunning != true {
            status?("Starting speech engine…")
            let p = Process()
            p.executableURL = serverBinary
            p.arguments = ["-m", modelFile.path,
                           "--host", "127.0.0.1", "--port", "\(port)",
                           "-t", "\(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))"]
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
            if await isListening() { status?("Speech engine ready."); return }
            if process?.isRunning != true {
                throw NSError(domain: "Ghostwriter", code: 7, userInfo: [NSLocalizedDescriptionKey:
                    "whisper-server exited early: see \(Self.logURL.path)"])
            }
            status?("Waiting for speech engine…")
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw NSError(domain: "Ghostwriter", code: 8,
                      userInfo: [NSLocalizedDescriptionKey: "whisper-server not ready in \(Int(readyTimeout))s"])
    }

    /// whisper-server exposes no stable health route across versions; any HTTP
    /// response proves the port is answering.
    private func isListening() async -> Bool {
        var req = URLRequest(url: baseURL)
        req.timeoutInterval = 2
        guard let (_, resp) = try? await session.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode,
              (200..<500).contains(code) else { return false }
        return true
    }

    public func transcribe(audio: [Float], contextPrompt: String?) async throws -> String {
        try await ensureRunning(readyTimeout: 300)
        var req = URLRequest(url: baseURL.appendingPathComponent("inference"))
        req.httpMethod = "POST"
        let boundary = "gw-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var form = Data()
        func field(_ name: String, _ value: String) {
            form.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("temperature", "0")
        field("response_format", "json")
        if let contextPrompt { field("prompt", contextPrompt) }
        form.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        form.append(Self.wavData(from: audio))
        form.append(Data("\r\n--\(boundary)--\r\n".utf8))
        req.httpBody = form
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw NSError(domain: "Ghostwriter", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "Bad whisper-server response"])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 16-bit PCM mono 16 kHz WAV wrapper around the pipeline's Float samples.
    static func wavData(from samples: [Float], sampleRate: Int = 16000) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let clamped = max(-1.0, min(1.0, s.isFinite ? s : 0))
            var v = Int16(clamped * 32767).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        var header = Data()
        func append(_ str: String) { header.append(Data(str.utf8)) }
        func append32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        append("RIFF"); append32(UInt32(36 + pcm.count)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2))
        append16(2); append16(16)
        append("data"); append32(UInt32(pcm.count))
        return header + pcm
    }

    public func shutdown() { process?.terminate(); process = nil }
}
