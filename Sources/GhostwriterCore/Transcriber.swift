public protocol Transcriber: AnyObject {
    /// contextPrompt biases recognition toward dictionary vocabulary.
    func transcribe(audio: [Float], contextPrompt: String?) async throws -> String
}
