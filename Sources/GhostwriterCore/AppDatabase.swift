import Foundation
import GRDB

public final class AppDatabase {
    let dbQueue: DatabaseQueue

    public static let defaultSeededTechnicalApps = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.microsoft.VSCode",
        "com.exafunction.windsurf", "com.todesktop.230313mzl4w4u92", // Cursor
        "com.apple.dt.Xcode", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ]

    public init(path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    public static func inMemory() throws -> AppDatabase { try AppDatabase(queue: DatabaseQueue()) }
    private init(queue: DatabaseQueue) throws {
        dbQueue = queue
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "dictation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("rawText", .text).notNull()
                t.column("cleanedText", .text).notNull()
                t.column("appBundleID", .text)
                t.column("durationSec", .double).notNull()
                t.column("usedFallback", .boolean).notNull()
                t.column("profileUsed", .text).notNull()
            }
            try db.create(virtualTable: "dictation_ft", using: FTS5()) { t in
                t.synchronize(withTable: "dictation")
                t.column("rawText"); t.column("cleanedText")
            }
            try db.create(table: "dictionaryTerm") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("term", .text).notNull().unique()
                t.column("aliases", .text).notNull()   // JSON array via Codable
            }
            try db.create(table: "appProfile") { t in
                t.column("bundleID", .text).primaryKey()
                t.column("mode", .text).notNull()
            }
            for bundle in Self.defaultSeededTechnicalApps {
                try AppProfileRecord(bundleID: bundle, mode: CleanupMode.verbatimTechnical.rawValue).insert(db)
            }
        }
        return m
    }

    // MARK: Dictations
    public func saveDictation(_ rec: DictationRecord) throws -> DictationRecord {
        try dbQueue.write { db in var r = rec; try r.insert(db); return r }
    }
    public func recentDictations(limit: Int = 200) throws -> [DictationRecord] {
        try dbQueue.read { db in
            try DictationRecord.order(Column("createdAt").desc).limit(limit).fetchAll(db)
        }
    }
    public func searchDictations(_ query: String) throws -> [DictationRecord] {
        let tokens = query.split(separator: " ").map { "\"\($0)\"" }.joined(separator: " ")
        guard !tokens.isEmpty else { return try recentDictations() }
        return try dbQueue.read { db in
            try DictationRecord.fetchAll(db, sql: """
                SELECT dictation.* FROM dictation
                JOIN dictation_ft ON dictation_ft.rowid = dictation.id
                WHERE dictation_ft MATCH ?
                ORDER BY createdAt DESC LIMIT 200
                """, arguments: [tokens])
        }
    }

    // MARK: Dictionary
    public func allTerms() throws -> [DictionaryTerm] {
        try dbQueue.read { db in try DictionaryTerm.order(Column("term")).fetchAll(db) }
    }
    public func addTerm(_ term: DictionaryTerm) throws {
        try dbQueue.write { db in var t = term; try t.insert(db) }
    }
    public func deleteTerm(id: Int64) throws {
        _ = try dbQueue.write { db in try DictionaryTerm.deleteOne(db, key: id) }
    }

    // MARK: App profiles
    public func mode(forBundleID bundleID: String?) throws -> CleanupMode {
        guard let bundleID else { return .lightTouch }
        return try dbQueue.read { db in
            guard let rec = try AppProfileRecord.fetchOne(db, key: bundleID),
                  let mode = CleanupMode(rawValue: rec.mode) else { return .lightTouch }
            return mode
        }
    }
    public func setMode(_ mode: CleanupMode, forBundleID bundleID: String) throws {
        try dbQueue.write { db in
            try AppProfileRecord(bundleID: bundleID, mode: mode.rawValue).save(db)
        }
    }
    public func removeProfile(bundleID: String) throws {
        _ = try dbQueue.write { db in try AppProfileRecord.deleteOne(db, key: bundleID) }
    }
    public func allProfiles() throws -> [(bundleID: String, mode: CleanupMode)] {
        try dbQueue.read { db in
            try AppProfileRecord.order(Column("bundleID")).fetchAll(db)
                .compactMap { r in CleanupMode(rawValue: r.mode).map { (r.bundleID, $0) } }
        }
    }
}
