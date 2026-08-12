import AppKit

/// Quiet native earcons for recording boundaries. Keeping these separate from
/// the HUD makes the feedback work in every app, including full-screen ones.
@MainActor
final class RecordingFeedback {
    private let startSound = NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff",
                                     byReference: true)
    private let stopSound = NSSound(contentsOfFile: "/System/Library/Sounds/Pop.aiff",
                                    byReference: true)

    init() {
        startSound?.volume = 0.22
        stopSound?.volume = 0.22
    }

    func playStart() {
        startSound?.stop()
        startSound?.play()
    }

    func playStop() {
        stopSound?.stop()
        stopSound?.play()
    }
}
