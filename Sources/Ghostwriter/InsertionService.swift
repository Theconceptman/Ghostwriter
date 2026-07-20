import AppKit
import Carbon.HIToolbox

enum InsertionOutcome: Equatable {
    case pasted
    case copiedOnly(reason: String)
}

/// Clipboard-swap paste: save clipboard string, paste dictation via synthetic ⌘V,
/// restore the previous clipboard afterwards (spec §2). Requires Accessibility.
final class InsertionService {
    func insert(text: String) -> InsertionOutcome {
        let pasteboard = NSPasteboard.general
        if IsSecureEventInputEnabled() {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedOnly(reason: "A secure input field is active — text copied to clipboard instead.")
        }
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return .copiedOnly(reason: "Could not synthesize paste — text is on your clipboard.")
        }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)

        // Restore the user's clipboard once the paste has been consumed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let saved {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
        }
        return .pasted
    }
}
