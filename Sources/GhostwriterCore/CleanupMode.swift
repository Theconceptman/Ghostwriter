public enum CleanupMode: String, Codable, CaseIterable, Sendable {
    case lightTouch, verbatimTechnical, raw

    public var displayName: String {
        switch self {
        case .lightTouch: return "Light touch"
        case .verbatimTechnical: return "Verbatim technical"
        case .raw: return "Raw (no AI)"
        }
    }
}
