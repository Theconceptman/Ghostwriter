import AppKit
import Carbon.HIToolbox

enum HotkeyChoice: String, Codable, CaseIterable {
    case fn, rightCommand, rightOption
    var displayName: String {
        switch self {
        case .fn: return "Fn (Globe)"
        case .rightCommand: return "Right ⌘"
        case .rightOption: return "Right ⌥"
        }
    }
}

/// Watches modifier-key transitions system-wide via NSEvent global+local monitors.
/// Requires Accessibility trust. Press/release callbacks fire on the main thread.
/// Onboarding tells Fn users to set "Press 🌐 key to: Do Nothing" so taps don't
/// also open the emoji picker.
final class HotkeyService {
    var choice: HotkeyChoice = .fn
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private var monitors: [Any] = []
    private var isDown = false

    static func hasAccessibilityPermission() -> Bool { AXIsProcessTrusted() }
    static func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] event in self?.handle(event) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            handler(event); return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll(); isDown = false
    }

    private func handle(_ event: NSEvent) {
        let downNow: Bool
        switch choice {
        case .fn:
            downNow = event.modifierFlags.contains(.function)
        case .rightCommand:
            guard event.keyCode == UInt16(kVK_RightCommand) else { return }
            downNow = event.modifierFlags.contains(.command)
        case .rightOption:
            guard event.keyCode == UInt16(kVK_RightOption) else { return }
            downNow = event.modifierFlags.contains(.option)
        }
        guard downNow != isDown else { return }
        isDown = downNow
        DispatchQueue.main.async { [weak self] in
            downNow ? self?.onPress?() : self?.onRelease?()
        }
    }
}
