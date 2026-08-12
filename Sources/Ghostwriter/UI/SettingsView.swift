import SwiftUI
import ServiceManagement
import GhostwriterCore
import Carbon.HIToolbox

struct SettingsView: View {
    @State private var hotkey = AppState.shared.hotkey
    @State private var threshold = AppState.shared.guardrailThreshold
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var profiles: [(bundleID: String, mode: CleanupMode)] = []
    @State private var newBundleID = ""
    @State private var newMode: CleanupMode = .verbatimTechnical
    @State private var showAdvanced = false
    @State private var isRecordingHotkey = false
    @State private var recordingStatus = ""

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Picker("Hold to dictate:", selection: $hotkey) {
                        ForEach(HotkeyChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .onChange(of: hotkey) { _, v in
                        AppState.shared.hotkey = v
                        (NSApp.delegate as? AppDelegate)?.hotkeyChanged()
                    }
                    Button(isRecordingHotkey ? "Listening…" : "Auto-detect") {
                        if !isRecordingHotkey {
                            startHotkeyRecording()
                        }
                    }
                    .disabled(isRecordingHotkey)
                }
                if !recordingStatus.isEmpty {
                    Text(recordingStatus)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Control supports hold-to-talk and double-tap hands-free mode. Press ⌃⌘V to paste your latest dictation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Per-app modes") {
                ForEach(profiles, id: \.bundleID) { p in
                    HStack {
                        Text(p.bundleID)
                        Spacer()
                        Text(p.mode.displayName).foregroundStyle(.secondary)
                        Button { remove(p.bundleID) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Picker("App:", selection: $newBundleID) {
                        Text("Choose running app…").tag("")
                        ForEach(runningApps(), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Mode:", selection: $newMode) {
                        ForEach(CleanupMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Button("Add") { addProfile() }.disabled(newBundleID.isEmpty)
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        try? v ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading) {
                        Text("Guardrail strictness — how much the cleanup may deviate before Ghostwriter falls back to your exact words. Lower = stricter.")
                            .font(.caption).foregroundStyle(.secondary)
                        Slider(value: $threshold, in: 0.05...0.4, step: 0.05) {
                            Text("Threshold")
                        } minimumValueLabel: { Text("strict") } maximumValueLabel: { Text("loose") }
                        .onChange(of: threshold) { _, v in AppState.shared.guardrailThreshold = v }
                        Text(String(format: "Current: %.2f (default 0.15)", threshold)).font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { profiles = (try? AppState.shared.db.allProfiles()) ?? [] }
    }

    private func startHotkeyRecording() {
        isRecordingHotkey = true
        recordingStatus = "Hold any key…"
        var monitor: Any?
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            var detected: HotkeyChoice?

            if event.type == .keyDown {
                if event.keyCode == UInt16(kVK_Control) || event.keyCode == UInt16(kVK_RightControl) {
                    detected = .control
                } else if event.keyCode == UInt16(kVK_RightCommand) {
                    detected = .rightCommand
                } else if event.keyCode == UInt16(kVK_RightOption) {
                    detected = .rightOption
                }
            } else if event.type == .flagsChanged {
                if event.modifierFlags.contains(.function) {
                    detected = .fn
                } else if event.modifierFlags.contains(.command) && event.keyCode == UInt16(kVK_RightCommand) {
                    detected = .rightCommand
                } else if event.modifierFlags.contains(.option) && event.keyCode == UInt16(kVK_RightOption) {
                    detected = .rightOption
                }
            }

            DispatchQueue.main.async {
                if let detected {
                    hotkey = detected
                    AppState.shared.hotkey = detected
                    (NSApp.delegate as? AppDelegate)?.hotkeyChanged()
                    recordingStatus = "✓ Set to \(detected.displayName)"
                    isRecordingHotkey = false
                    if let m = monitor { NSEvent.removeMonitor(m) }
                } else if !recordingStatus.contains("Unsupported") {
                    recordingStatus = "Unsupported key. Try: Control, Fn, Right ⌘, or Right ⌥"
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if isRecordingHotkey {
                isRecordingHotkey = false
                recordingStatus = "Timed out. Try again."
                if let m = monitor { NSEvent.removeMonitor(m) }
            }
        }
    }

    private func runningApps() -> [String] {
        NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
            .filter { !$0.hasPrefix("com.apple.") || $0 == "com.apple.Terminal" || $0 == "com.apple.dt.Xcode" }
            .sorted()
    }
    private func addProfile() {
        try? AppState.shared.db.setMode(newMode, forBundleID: newBundleID)
        profiles = (try? AppState.shared.db.allProfiles()) ?? []
        newBundleID = ""
    }
    private func remove(_ bundleID: String) {
        try? AppState.shared.db.removeProfile(bundleID: bundleID)
        profiles = (try? AppState.shared.db.allProfiles()) ?? []
    }
}
