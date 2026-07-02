import Foundation
@testable import hark
import Testing

struct SessionMetadataTests {
    // MARK: Codable

    @Test func decodesEmptyObjectLeniently() throws {
        let metadata = try JSONDecoder().decode(SessionMetadata.self, from: Data("{}".utf8))
        #expect(metadata.name == nil)
        #expect(metadata.tags.isEmpty)
    }

    @Test func toleratesUnknownKeys() throws {
        let json = Data(#"{"name":"Standup","color":"red"}"#.utf8)
        let metadata = try JSONDecoder().decode(SessionMetadata.self, from: json)
        #expect(metadata.name == "Standup")
    }

    @Test func roundTripsNameAndTags() throws {
        let metadata = SessionMetadata(name: "Standup", tags: ["Work", "1:1"])
        let data = try JSONEncoder().encode(metadata)
        #expect(try JSONDecoder().decode(SessionMetadata.self, from: data) == metadata)
    }

    @Test func omitsEmptyFieldsWhenEncoding() throws {
        // An untouched metadata encodes to a bare object, so "nothing assigned" has one representation.
        let json = try #require(try String(bytes: JSONEncoder().encode(SessionMetadata()), encoding: .utf8))
        #expect(!json.contains("name"))
        #expect(!json.contains("tags"))
    }

    // MARK: Tag editing

    /// `#expect` can't call a mutating member on its captured receiver, so the adds are hoisted out.
    @Test func addTagTrimsAndKeepsInsertionOrder() {
        var metadata = SessionMetadata()
        let addedWork = metadata.addTag("  Work ")
        let addedOneOnOne = metadata.addTag("1:1")
        #expect(addedWork)
        #expect(addedOneOnOne)
        #expect(metadata.tags == ["Work", "1:1"])
    }

    @Test func addTagRejectsBlanksAndCaseInsensitiveDuplicates() {
        var metadata = SessionMetadata(tags: ["Work"])
        let addedBlank = metadata.addTag("   ")
        let addedDuplicate = metadata.addTag("work")
        #expect(!addedBlank)
        #expect(!addedDuplicate)
        #expect(metadata.tags == ["Work"])
    }

    @Test func removesATag() {
        var metadata = SessionMetadata(tags: ["Work", "1:1"])
        metadata.removeTag("Work")
        #expect(metadata.tags == ["1:1"])
    }

    // MARK: SessionSummary title precedence

    private let url = URL(fileURLWithPath: "/recordings/hark-20260101-120000")

    @Test func titlePrefersTheCustomName() {
        let summary = SessionSummary(url: url, date: .distantPast, metadata: SessionMetadata(name: "Standup"))
        #expect(summary.title == "Standup")
        #expect(summary.name == "Standup")
    }

    @Test func titleFallsBackToTheDate() {
        let summary = SessionSummary(url: url, date: .distantPast)
        #expect(summary.name == nil)
        #expect(summary.title == summary.dateLabel)
    }
}
