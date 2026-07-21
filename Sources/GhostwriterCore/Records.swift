import Foundation
import GRDB

public struct DictationRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "dictation"
    public var id: Int64?
    public var createdAt: Date
    public var rawText: String
    public var cleanedText: String
    public var appBundleID: String?
    public var durationSec: Double
    public var usedFallback: Bool
    public var profileUsed: String

    public init(id: Int64? = nil, createdAt: Date, rawText: String, cleanedText: String,
                appBundleID: String?, durationSec: Double, usedFallback: Bool, profileUsed: String) {
        self.id = id; self.createdAt = createdAt; self.rawText = rawText
        self.cleanedText = cleanedText; self.appBundleID = appBundleID
        self.durationSec = durationSec; self.usedFallback = usedFallback; self.profileUsed = profileUsed
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension DictionaryTerm: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "dictionaryTerm" }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

struct AppProfileRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appProfile"
    var bundleID: String
    var mode: String
}
