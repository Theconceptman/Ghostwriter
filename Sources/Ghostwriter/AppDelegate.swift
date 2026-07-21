import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = StatusItemController()
    private let dictation = DictationController()
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar only (LSUIElement)
        statusItem.install()
        statusItem.onOpenMain = { [weak self] in self?.showMainWindow() }
        dictation.onStatusChange = { [weak self] text in self?.statusItem.lastDictation = text }

        if AppState.shared.hasOnboarded && HotkeyService.hasAccessibilityPermission() {
            dictation.start()
        } else {
            showOnboarding()
        }
        if CommandLine.arguments.contains("--open-main") { showMainWindow() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.cleaner.shutdown()
    }

    func showMainWindow() {
        if mainWindow == nil {
            let host = NSHostingController(rootView: MainWindow())
            let w = NSWindow(contentViewController: host)
            w.title = "Ghostwriter"
            w.setContentSize(NSSize(width: 720, height: 520))
            w.isReleasedWhenClosed = false
            mainWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView(
                onReadyToTest: { [weak self] in
                    // Dictation goes live for the "try it" step while onboarding stays open.
                    self?.dictation.start()
                },
                onComplete: { [weak self] in
                    AppState.shared.hasOnboarded = true
                    self?.onboardingWindow?.orderOut(nil)
                }))
            let w = NSWindow(contentViewController: host)
            w.title = "Welcome to Ghostwriter"
            w.setContentSize(NSSize(width: 560, height: 560))
            w.isReleasedWhenClosed = false
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func hotkeyChanged() { dictation.updateHotkey() }
}
