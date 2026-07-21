import Foundation
import GhostwriterML

@MainActor
final class ModelManager: ObservableObject {
    @Published var status = "Not started"
    @Published var ready = false
    @Published var failed = false

    /// Installs llama.cpp via Homebrew if missing, then downloads/loads both models.
    func prepareAll() async {
        failed = false
        do {
            if !LlamaServerCleaner.binaryExists() {
                status = "Installing llama.cpp via Homebrew…"
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
                p.arguments = ["install", "llama.cpp"]
                try p.run()
                await withCheckedContinuation { cont in
                    p.terminationHandler = { _ in cont.resume() }
                }
                guard p.terminationStatus == 0, LlamaServerCleaner.binaryExists() else {
                    throw NSError(domain: "Ghostwriter", code: 5, userInfo: [NSLocalizedDescriptionKey:
                        "Homebrew install failed — run `brew install llama.cpp` in Terminal, then retry."])
                }
            }
            status = "Downloading speech model (one-time, ~1.6 GB)…"
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
}
