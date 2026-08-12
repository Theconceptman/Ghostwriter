import Testing
@testable import GhostwriterCore

@Suite struct ControlGestureInterpreterTests {
    @Test func holdProducesPressThenRelease() {
        var gesture = ControlGestureInterpreter()
        #expect(gesture.handle(isDown: true, at: 1.0, isLatched: false) == .press)
        #expect(gesture.handle(isDown: false, at: 2.0, isLatched: false) == .release)
    }

    @Test func secondQuickTapTogglesLatchAndSuppressesRelease() {
        var gesture = ControlGestureInterpreter()
        #expect(gesture.handle(isDown: true, at: 1.0, isLatched: false) == .press)
        #expect(gesture.handle(isDown: false, at: 1.1, isLatched: false) == .release)
        #expect(gesture.handle(isDown: true, at: 1.2, isLatched: false) == .toggleLatch)
        #expect(gesture.handle(isDown: false, at: 1.3, isLatched: true) == .ignore)
    }

    @Test func doubleTapWhileLatchedStopsOnSecondPress() {
        var gesture = ControlGestureInterpreter()
        #expect(gesture.handle(isDown: true, at: 3.0, isLatched: true) == .ignore)
        #expect(gesture.handle(isDown: false, at: 3.1, isLatched: true) == .ignore)
        #expect(gesture.handle(isDown: true, at: 3.2, isLatched: true) == .toggleLatch)
        #expect(gesture.handle(isDown: false, at: 3.3, isLatched: false) == .ignore)
    }

    @Test func slowSecondTapStartsAnotherHold() {
        var gesture = ControlGestureInterpreter()
        #expect(gesture.handle(isDown: true, at: 1.0, isLatched: false) == .press)
        #expect(gesture.handle(isDown: false, at: 1.1, isLatched: false) == .release)
        #expect(gesture.handle(isDown: true, at: 1.5, isLatched: false) == .press)
    }

    @Test func duplicateModifierEventsAreIgnored() {
        var gesture = ControlGestureInterpreter()
        #expect(gesture.handle(isDown: true, at: 1.0, isLatched: false) == .press)
        #expect(gesture.handle(isDown: true, at: 1.01, isLatched: false) == .ignore)
    }
}
