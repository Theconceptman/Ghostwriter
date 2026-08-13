import Foundation
import GhostwriterCore
import GhostwriterML

@MainActor
final class AppState {
    static let shared = AppState()
    let db: AppDatabase
    // Engine per slice: WhisperKit's CoreML pipeline traps on x86_64
    // (EXC_BAD_ACCESS in TextDecoding.prepareDecoderInputs, crash report
    // verified 2026-08-12; see the Intel fallback decision record). whisper.cpp
    // runs out of process on Intel, so an engine crash cannot take the app down.
    #if arch(x86_64)
    let transcriber = WhisperCppTranscriber()
    #else
    let transcriber = WhisperTranscriber()
    #endif
    let cleaner = LlamaServerCleaner()

    private let defaults = UserDefaults.standard

    var hotkey: HotkeyChoice {
        get { HotkeyChoice(rawValue: defaults.string(forKey: "hotkey") ?? "control") ?? .control }
        set {
            defaults.set(newValue.rawValue, forKey: "hotkey")
            defaults.synchronize()
        }
    }
    var guardrailThreshold: Double {
        get { defaults.object(forKey: "guardrailThreshold") as? Double ?? FidelityGuardrail.defaultThreshold }
        set {
            defaults.set(newValue, forKey: "guardrailThreshold")
            defaults.synchronize()
        }
    }
    var isPaused: Bool {
        get { defaults.bool(forKey: "isPaused") }
        set {
            defaults.set(newValue, forKey: "isPaused")
            defaults.synchronize()
        }
    }
    var hasOnboarded: Bool {
        get { defaults.bool(forKey: "hasOnboarded") }
        set {
            defaults.set(newValue, forKey: "hasOnboarded")
            defaults.synchronize()
        }
    }

    private init() {
        let path: String
        if let override = ProcessInfo.processInfo.environment["GW_DB_PATH"] {
            path = override   // dev/verification runs stay out of the real history
        } else {
            path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Ghostwriter/ghostwriter.sqlite").path
        }
        // A dictation app that can't open its history DB can't run meaningfully;
        // crashing at launch with a clear path beats limping along silently.
        db = try! AppDatabase(path: path)
    }
}

extension Notification.Name {
    static let gwHistoryChanged = Notification.Name("gwHistoryChanged")
}
