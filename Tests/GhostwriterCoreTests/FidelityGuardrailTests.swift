import Testing
@testable import GhostwriterCore

@Suite struct FidelityGuardrailTests {
    @Test func identicalTextAccepted() {
        let v = FidelityGuardrail.evaluate(raw: "ship the fix today", cleaned: "Ship the fix today.")
        #expect(v.accepted)
        #expect(v.penalty == 0)
    }
    @Test func fillerRemovalIsFree() {
        let v = FidelityGuardrail.evaluate(
            raw: "um so basically I want uh the button blue you know",
            cleaned: "So basically I want the button blue.")
        #expect(v.accepted)
        #expect(v.penalty == 0)
    }
    @Test func selfCorrectionSpanIsFree() {
        let v = FidelityGuardrail.evaluate(
            raw: "send it Tuesday no wait send it Wednesday morning",
            cleaned: "Send it Wednesday morning.")
        #expect(v.accepted)
    }
    @Test func fullRewriteRejected() {
        let v = FidelityGuardrail.evaluate(
            raw: "make the login page way faster please it is really slow for users",
            cleaned: "Optimize authentication latency to improve user experience.")
        #expect(!v.accepted)
    }
    @Test func emptyCleanedRejected() {
        #expect(!FidelityGuardrail.evaluate(raw: "hello there", cleaned: "").accepted)
    }
    @Test func emptyRawAccepted() {
        #expect(FidelityGuardrail.evaluate(raw: "", cleaned: "").accepted)
    }
    @Test func shortUtteranceSmallInsertRejected() {
        // 3-word utterance, 2 inserted words -> penalty 2.0 > allowance max(0.45, 1.5)
        let v = FidelityGuardrail.evaluate(raw: "fix the bug", cleaned: "please kindly fix the bug")
        #expect(!v.accepted)
    }
    @Test func modestNonFillerDeletionTolerated() {
        // deleting 2 non-filler words costs 0.5, allowance >= 1.5
        let v = FidelityGuardrail.evaluate(
            raw: "so yeah make the header sticky on scroll",
            cleaned: "Make the header sticky on scroll.")
        #expect(v.accepted)
    }
}
