import Testing
@testable import GhostwriterCore

@Suite struct SmokeTests {
    @Test func version() {
        #expect(GhostwriterCore.version == "1.0.0")
    }
}
