import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem!
    private let state = AppState.shared
    var lastDictation: String = ""
    var onOpenMain: (() -> Void)?

    func install() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill",
                                   accessibilityDescription: "Ghostwriter")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let pauseTitle = state.isPaused ? "Resume Ghostwriter" : "Pause Ghostwriter"
        menu.addItem(withTitle: pauseTitle, action: #selector(togglePause), keyEquivalent: "p").target = self
        if !lastDictation.isEmpty {
            let preview = lastDictation.count > 48 ? String(lastDictation.prefix(48)) + "…" : lastDictation
            let copyItem = NSMenuItem(title: "Copy last: “\(preview)”",
                                      action: #selector(copyLast), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Ghostwriter…", action: #selector(openMain), keyEquivalent: "o").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ghostwriter", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func togglePause() { state.isPaused.toggle() }
    @objc private func copyLast() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastDictation, forType: .string)
    }
    @objc private func openMain() { onOpenMain?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
