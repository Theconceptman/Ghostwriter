public protocol TextCleaner: AnyObject {
    func clean(transcript: String, systemPrompt: String) async throws -> String
}
