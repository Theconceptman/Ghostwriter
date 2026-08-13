import SwiftUI
import AVFoundation

struct OnboardingView: View {
    let onReadyToTest: () -> Void
    let onComplete: () -> Void
    @State private var step = 0
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = HotkeyService.hasAccessibilityPermission()
    @State private var tryItText = ""
    @StateObject private var models = ModelManager()
    @State private var axTimer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Text("👻").font(.system(size: 56))
            switch step {
            case 0: welcome
            case 1: microphone
            case 2: accessibility
            case 3: globeKey
            case 4: modelSetup
            default: tryIt
            }
            Spacer()
        }
        .padding(32)
        .frame(width: 560, height: 560)
        .onAppear { refreshAccessibilityPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityPermission()
        }
        .onDisappear {
            axTimer?.invalidate()
            axTimer = nil
        }
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Text("Welcome to Ghostwriter").font(.title.bold())
            Text("Hold a key, speak, release — your words appear, cleaned up but never rewritten. Everything runs on this Mac. Nothing is uploaded, ever.")
                .multilineTextAlignment(.center)
            Button("Set up (about 10 minutes, one time)") { step = 1 }
                .buttonStyle(.borderedProminent)
        }
    }
    private var microphone: some View {
        VStack(spacing: 12) {
            Text("Microphone access").font(.title2.bold())
            Text("Ghostwriter needs the mic to hear you. Audio is processed locally and never stored.")
                .multilineTextAlignment(.center)
            Button(micGranted ? "✓ Granted" : "Allow microphone") {
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async { micGranted = ok; if ok { step = 2 } }
                }
            }.buttonStyle(.borderedProminent).disabled(micGranted)
            if micGranted { Button("Continue") { step = 2 } }
        }
    }
    private var accessibility: some View {
        VStack(spacing: 12) {
            Text("Accessibility access").font(.title2.bold())
            Text("This lets Ghostwriter notice your hotkey in any app and type the result at your cursor — the same permission other dictation apps use. macOS will open System Settings; enable Ghostwriter, then come back here.")
                .multilineTextAlignment(.center)
            Button(axGranted ? "✓ Granted" : "Open System Settings") {
                HotkeyService.requestAccessibilityPermission()
                axTimer?.invalidate()
                axTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    refreshAccessibilityPermission()
                }
            }.buttonStyle(.borderedProminent).disabled(axGranted)
            if axGranted { Button("Continue") { step = 3 } }
        }
    }

    private func refreshAccessibilityPermission() {
        axGranted = HotkeyService.hasAccessibilityPermission()
        if axGranted {
            axTimer?.invalidate()
            axTimer = nil
        }
    }
    private var globeKey: some View {
        VStack(spacing: 12) {
            Text("One macOS setting").font(.title2.bold())
            Text("So holding Fn doesn't also open the emoji picker:\n\nSystem Settings → Keyboard → “Press 🌐 key to” → Do Nothing")
                .multilineTextAlignment(.center)
            Button("Open Keyboard Settings") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
            Button("Done — continue") { step = 4; Task { await models.prepareAll() } }
                .buttonStyle(.borderedProminent)
        }
    }
    private var modelSetup: some View {
        VStack(spacing: 12) {
            Text("Downloading your models").font(.title2.bold())
            #if arch(x86_64)
            Text("Two one-time downloads (~3 GB total). This Mac uses a compact speech model tuned for Intel; transcription takes a few seconds per phrase. After this, Ghostwriter is fully offline and free forever.")
                .multilineTextAlignment(.center)
            #else
            Text("Two one-time downloads (~4 GB total). After this, Ghostwriter is fully offline and free forever.")
                .multilineTextAlignment(.center)
            #endif
            ProgressView().opacity(models.ready || models.failed ? 0 : 1)
            Text(models.status).font(.callout)
                .foregroundStyle(models.failed ? .red : .secondary)
                .multilineTextAlignment(.center)
            if models.failed { Button("Retry") { Task { await models.prepareAll() } } }
            if models.ready {
                Button("Continue") { step = 5; onReadyToTest() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
    private var tryIt: some View {
        VStack(spacing: 12) {
            Text("Try it!").font(.title2.bold())
            Text("Click into the box below, hold Fn, say something like “um, hello Ghostwriter, this is, uh, my first dictation”, and release.")
                .multilineTextAlignment(.center)
            #if arch(x86_64)
            Text("On this Mac, expect a few seconds before the words land.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            #endif
            TextEditor(text: $tryItText).frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
            Button("Finish setup") { onComplete() }.buttonStyle(.borderedProminent)
        }
    }
}
