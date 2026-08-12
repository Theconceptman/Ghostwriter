import Foundation

public enum ControlGestureAction: Equatable {
    case press
    case release
    case toggleLatch
    case ignore
}

/// Interprets Control modifier transitions without depending on AppKit so the
/// hold and double-tap behavior can be tested deterministically.
public struct ControlGestureInterpreter {
    private let doubleTapInterval: TimeInterval
    private var isDown = false
    private var lastDown: TimeInterval?
    private var suppressRelease = false

    public init(doubleTapInterval: TimeInterval = 0.35) {
        self.doubleTapInterval = doubleTapInterval
    }

    public mutating func handle(isDown down: Bool, at timestamp: TimeInterval,
                                isLatched: Bool) -> ControlGestureAction {
        guard down != isDown else { return .ignore }
        isDown = down

        if down {
            if let lastDown, timestamp - lastDown <= doubleTapInterval {
                self.lastDown = nil
                suppressRelease = true
                return .toggleLatch
            }
            lastDown = timestamp
            if isLatched {
                suppressRelease = true
                return .ignore
            }
            return .press
        }

        if suppressRelease || isLatched {
            suppressRelease = false
            return .ignore
        }
        return .release
    }

    public mutating func reset() {
        isDown = false
        lastDown = nil
        suppressRelease = false
    }
}
