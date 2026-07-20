public struct DictionaryTerm: Codable, Equatable {
    public var id: Int64?
    public var term: String
    public var aliases: [String]
    public init(id: Int64? = nil, term: String, aliases: [String] = []) {
        self.id = id; self.term = term; self.aliases = aliases
    }
}
