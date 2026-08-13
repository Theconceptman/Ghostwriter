import Foundation
import GhostwriterML

@MainActor
final class ModelManager: ObservableObject {
    @Published var status = "Not started"
    @Published var ready = false
    @Published var failed = false

    /// Installs engine binaries via Homebrew if missing, then downloads/loads all models.
    func prepareAll() async {
        failed = false
        do {
            try await installIfMissing("llama.cpp", exists: LlamaServerCleaner.binaryExists)
            #if arch(x86_64)
            // Intel transcription runs on whisper.cpp out of process; WhisperKit's
            // CoreML pipeline traps on x86_64 (crash report verified 2026-08-12).
            try await installIfMissing("whisper-cpp", exists: WhisperCppTranscriber.binaryExists)
            status = "Downloading speech model (one-time, ~0.5 GB)…"
            #else
            status = "Downloading speech model (one-time, ~1.6 GB)…"
            #endif
            let transcriber = AppState.shared.transcriber
            try await transcriber.preload { [weak self] s in
                Task { @MainActor in self?.status = s }
            }
            status = "Downloading cleanup model (one-time, ~2.4 GB)…"
            let cleaner = AppState.shared.cleaner
            try await cleaner.ensureRunning(readyTimeout: 3600) { [weak self] s in
                Task { @MainActor in self?.status = s }
            }
            status = "All models ready."
            ready = true
        } catch {
            status = "Setup failed: \(error.localizedDescription)"
            failed = true
        }
    }

    private func installIfMissing(_ formula: String, exists: () -> Bool) async throws {
        guard !exists() else { return }
        status = "Installing \(formula) via Homebrew…"
        let brewPaths = [
            "/opt/homebrew/bin/brew",  // Apple Silicon
            "/usr/local/bin/brew"       // Intel
        ]
        guard let brewPath = brewPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw NSError(domain: "Ghostwriter", code: 5, userInfo: [NSLocalizedDescriptionKey:
                "Homebrew not found. Install it first: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\", then retry."])
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: brewPath)
        p.arguments = ["install", formula]
        try p.run()
        await withCheckedContinuation { cont in
            p.terminationHandler = { _ in cont.resume() }
        }
        guard p.terminationStatus == 0, exists() else {
            throw NSError(domain: "Ghostwriter", code: 5, userInfo: [NSLocalizedDescriptionKey:
                "Homebrew install failed — run `brew install \(formula)` in Terminal, then retry."])
        }
    }
}
