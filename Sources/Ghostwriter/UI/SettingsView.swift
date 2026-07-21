import SwiftUI
import ServiceManagement
import GhostwriterCore

struct SettingsView: View {
    @State private var hotkey = AppState.shared.hotkey
    @State private var threshold = AppState.shared.guardrailThreshold
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var profiles: [(bundleID: String, mode: CleanupMode)] = []
    @State private var newBundleID = ""
    @State private var newMode: CleanupMode = .verbatimTechnical
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Hotkey") {
                Picker("Hold to dictate:", selection: $hotkey) {
                    ForEach(HotkeyChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: hotkey) { _, v in
                    AppState.shared.hotkey = v
                    (NSApp.delegate as? AppDelegate)?.hotkeyChanged()
                }
                Text("Fn users: set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.")
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
