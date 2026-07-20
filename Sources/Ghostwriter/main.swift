import AppKit

// Top-level code runs on the main thread; make that visible to the compiler.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.run()
}
