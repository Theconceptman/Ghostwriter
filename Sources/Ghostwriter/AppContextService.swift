import AppKit
import GhostwriterCore

/// Captures the frontmost app at hotkey-down (before our HUD can interfere)
/// and maps it to a cleanup mode via stored profiles (spec §5).
final class AppContextService {
    private let db: AppDatabase
    init(db: AppDatabase) { self.db = db }

    func snapshotFrontmost() -> (bundleID: String?, mode: CleanupMode) {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let mode = (try? db.mode(forBundleID: bundleID)) ?? .lightTouch
        return (bundleID, mode)
    }
}
