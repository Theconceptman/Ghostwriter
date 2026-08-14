import AppKit
import GhostwriterCore

/// The state machine: idle -> recording -> processing -> idle.
/// Press starts capture instantly; release under 0.25s cancels (accidental tap).
@MainActor
final class DictationController {
    private let state = AppState.shared
    private let hotkey = HotkeyService()
    private let audio = AudioCaptureService()
    private let hud = HUDController()
    private let feedback = RecordingFeedback()
    private let insertion = InsertionService()
    private lazy var appContext = AppContextService(db: state.db)

    private var recordingStart: Date?
    private var snapshot: (bundleID: String?, mode: CleanupMode) = (nil, .raw)
    private var isProcessing = false
    private var isLatched = false

    var onStatusChange: ((String) -> Void)?   // feeds the status item's "last dictation"

    func start() {
        hotkey.choice = state.hotkey
        hotkey.onPress = { [weak self] in self?.pressed() }
        hotkey.onRelease = { [weak self] in self?.released() }
        hotkey.onLatchToggle = { [weak self] in self?.toggleLatchedRecording() }
        hotkey.onPasteLast = { [weak self] in self?.pasteLastDictation() }
        hotkey.start()
        audio.onLevel = { [weak self] level in self?.hud.updateLevel(level) }
        let transcriber = state.transcriber
        let cleaner = state.cleaner
        Task.detached {
            // Warm STT at launch and pay the first-inference cost now,
            // not on the user's first dictation.
            try? await transcriber.preload()
            _ = try? await transcriber.transcribe(
                audio: [Float](repeating: 0, count: 16000), contextPrompt: nil)
        }
        Task.detached { try? await cleaner.ensureRunning(readyTimeout: 600) } // warm LLM at launch
    }

    func updateHotkey() { hotkey.choice = state.hotkey }

    private func pressed() {
        guard !state.isPaused, !isProcessing, recordingStart == nil else { return }
        snapshot = appContext.snapshotFrontmost()
        do {
            try audio.start()
            recordingStart = Date()
            hud.showRecording()
            feedback.playStart()
        } catch {
            notify("Microphone unavailable", body: error.localizedDescription)
        }
    }

    private func released() {
        guard let started = recordingStart else { return }
        recordingStart = nil
        let duration = -started.timeIntervalSinceNow
        if duration < 0.25 {
            audio.cancel()
            feedback.playStop()
            hud.hide()
            return
        }
        let samples = audio.stop()
        feedback.playStop()
        hud.showProcessing()
        isProcessing = true
        let (bundleID, mode) = snapshot
        Task { [weak self] in
            guard let self else { return }
            let pipeline = DictationPipeline(transcriber: state.transcriber, cleaner: state.cleaner)
            let dictionary = (try? state.db.allTerms()) ?? []
            let result = await pipeline.process(audio: samples, mode: mode,
                                                dictionary: dictionary,
                                                guardrailThreshold: state.guardrailThreshold)
            self.finish(result: result, bundleID: bundleID, duration: duration)
        }
    }

    private func toggleLatchedRecording() {
        if isLatched {
            isLatched = false
            hotkey.isLatched = false
            released()
        } else {
            pressed()
            isLatched = recordingStart != nil
            hotkey.isLatched = isLatched
        }
    }

    private func pasteLastDictation() {
        // Pressing Control as part of ⌃⌘V may have started a normal hold. Cancel
        // that short capture before pasting; a deliberately latched recording stays on.
        if recordingStart != nil && !isLatched {
            recordingStart = nil
            audio.cancel()
            feedback.playStop()
            hud.hide()
        }

        guard let text = try? state.db.recentDictations(limit: 1).first?.cleanedText,
              !text.isEmpty else {
            notify("No previous dictation", body: "Dictate something first, then press Control–Command–V.")
            return
        }
        let outcome = insertion.insert(text: text)
        if case .copiedOnly(let reason) = outcome { notify("Copied instead", body: reason) }
    }

    private func finish(result: PipelineResult, bundleID: String?, duration: TimeInterval) {
        isProcessing = false
        if let err = result.errorDescription {
            hud.hide(); notify("Dictation failed", body: err); return
        }
        guard !result.finalText.isEmpty else { hud.hide(); return }

        let outcome = insertion.insert(text: result.finalText)
        hud.flashResult(fallback: result.usedFallback)
        if case .copiedOnly(let reason) = outcome { notify("Copied instead", body: reason) }

        let rec = DictationRecord(createdAt: Date(), rawText: result.rawText,
                                  cleanedText: result.finalText, appBundleID: bundleID,
                                  durationSec: duration, usedFallback: result.usedFallback,
                                  profileUsed: result.mode.rawValue)
        _ = try? state.db.saveDictation(rec)
        NotificationCenter.default.post(name: .gwHistoryChanged, object: nil)
        onStatusChange?(result.finalText)
    }

    private func notify(_ title: String, body: String) {
        // NSUserNotification is deprecated but works without the notification-permission
        // ceremony UNUserNotificationCenter requires; revisit in v1.1.
        let n = NSUserNotification()
        n.title = title; n.informativeText = body
        NSUserNotificationCenter.default.deliver(n)
    }
}
