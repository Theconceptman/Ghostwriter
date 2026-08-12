import AppKit
import Carbon.HIToolbox
import GhostwriterCore

enum HotkeyChoice: String, Codable, CaseIterable {
    case control, fn, rightCommand, rightOption
    var displayName: String {
        switch self {
        case .control: return "Control (⌃)"
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
    var onLatchToggle: (() -> Void)?
    var onPasteLast: (() -> Void)?
    var isLatched = false
    private var monitors: [Any] = []
    private var isDown = false
    private var controlGesture = ControlGestureInterpreter()

    static func hasAccessibilityPermission() -> Bool { AXIsProcessTrusted() }
    static func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            _ = self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event) == true ? nil : event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        isDown = false
        controlGesture.reset()
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            guard !event.isARepeat,
                  event.keyCode == UInt16(kVK_ANSI_V),
                  event.modifierFlags.contains(.control),
                  event.modifierFlags.contains(.command) else { return false }
            DispatchQueue.main.async { [weak self] in self?.onPasteLast?() }
            return true
        }

        if choice == .control {
            guard event.keyCode == UInt16(kVK_Control)
                    || event.keyCode == UInt16(kVK_RightControl) else { return false }
            let action = controlGesture.handle(
                isDown: event.modifierFlags.contains(.control),
                at: event.timestamp,
                isLatched: isLatched)
            DispatchQueue.main.async { [weak self] in
                switch action {
                case .press: self?.onPress?()
                case .release: self?.onRelease?()
                case .toggleLatch: self?.onLatchToggle?()
                case .ignore: break
                }
            }
            return false
        }

        let downNow: Bool
        switch choice {
        case .control: return false
        case .fn:
            downNow = event.modifierFlags.contains(.function)
        case .rightCommand:
            guard event.keyCode == UInt16(kVK_RightCommand) else { return false }
            downNow = event.modifierFlags.contains(.command)
        case .rightOption:
            guard event.keyCode == UInt16(kVK_RightOption) else { return false }
            downNow = event.modifierFlags.contains(.option)
        }

        guard downNow != isDown else { return false }
        isDown = downNow

        DispatchQueue.main.async { [weak self] in
            downNow ? self?.onPress?() : self?.onRelease?()
        }
        return false
    }
}
