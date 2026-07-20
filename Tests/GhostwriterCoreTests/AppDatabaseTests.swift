import Foundation
import Testing
@testable import GhostwriterCore

@Suite struct AppDatabaseTests {
    let db: AppDatabase
    init() throws { db = try AppDatabase.inMemory() }

    @Test func saveAndFetchDictation() throws {
        let rec = try db.saveDictation(DictationRecord(
            createdAt: Date(), rawText: "um hello", cleanedText: "Hello.",
            appBundleID: "com.apple.Terminal", durationSec: 2.5,
            usedFallback: false, profileUsed: "verbatimTechnical"))
        #expect(rec.id != nil)
        #expect(try db.recentDictations(limit: 10).first?.cleanedText == "Hello.")
    }
    @Test func fullTextSearch() throws {
        _ = try db.saveDictation(DictationRecord(
            createdAt: Date(), rawText: "deploy the supabase migration",
            cleanedText: "Deploy the Supabase migration.", appBundleID: nil, durationSec: 3,
            usedFallback: false, profileUsed: "lightTouch"))
        _ = try db.saveDictation(DictationRecord(
            createdAt: Date(), rawText: "buy milk",
            cleanedText: "Buy milk.", appBundleID: nil, durationSec: 1,
            usedFallback: false, profileUsed: "lightTouch"))
        let hits = try db.searchDictations("supabase")
        #expect(hits.count == 1)
        #expect(hits[0].cleanedText.contains("Supabase"))
    }
    @Test func dictionaryCRUD() throws {
        try db.addTerm(DictionaryTerm(term: "Ghostwriter", aliases: ["ghost writer"]))
        var terms = try db.allTerms()
        #expect(terms.map(\.term) == ["Ghostwriter"])
        #expect(terms[0].aliases == ["ghost writer"])
        try db.deleteTerm(id: terms[0].id!)
        terms = try db.allTerms()
        #expect(terms.isEmpty)
    }
    @Test func profilesSeededAndOverridable() throws {
        #expect(try db.mode(forBundleID: "com.apple.Terminal") == .verbatimTechnical)
        #expect(try db.mode(forBundleID: "com.unknown.app") == .lightTouch)
        #expect(try db.mode(forBundleID: nil) == .lightTouch)
        try db.setMode(.raw, forBundleID: "com.unknown.app")
        #expect(try db.mode(forBundleID: "com.unknown.app") == .raw)
        try db.removeProfile(bundleID: "com.unknown.app")
        #expect(try db.mode(forBundleID: "com.unknown.app") == .lightTouch)
    }
}
