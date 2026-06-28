import FluidAudio
import Foundation
@testable import hark
import Testing

/// Exercises `SpeakerStore`'s cross-session matching with synthetic 256-d embeddings, so no model
/// download is needed (matching is pure vector math). Each test runs against its own temporary
/// voiceprint directory, cleaned up afterwards.
final class SpeakerStoreTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hark-speakerstore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A 256-d embedding with `leading` values at the front and zeros elsewhere.
    private func embedding(_ leading: [Float]) -> [Float] {
        var values = [Float](repeating: 0, count: SpeakerManager.embeddingSize)
        for (index, value) in leading.enumerated() {
            values[index] = value
        }
        return values
    }

    @Test func enrollsThenMatchesAcrossStores() async throws {
        let first = SpeakerStore(directory: directory)
        let enrolled = await first.resolve([SpeakerCluster(id: "S1", centroid: embedding([1]), duration: 12)])
        let id = try #require(enrolled["S1"]?.id)
        #expect(enrolled["S1"]?.name == nil) // new voiceprints are unnamed

        // A fresh store loads the persisted database and matches the same voice (near, not identical).
        let second = SpeakerStore(directory: directory)
        let matched = await second.resolve([SpeakerCluster(id: "S1", centroid: embedding([1, 0.02]), duration: 8)])
        #expect(matched["S1"]?.id == id)
    }

    @Test func unmatchedVoiceEnrollsAsNew() async throws {
        let store = SpeakerStore(directory: directory)
        let first = await store.resolve([SpeakerCluster(id: "S1", centroid: embedding([1]), duration: 10)])
        let idA = try #require(first["S1"]?.id)

        // Orthogonal embedding: cosine distance 1.0, well past the 0.65 threshold.
        let next = SpeakerStore(directory: directory)
        let second = await next.resolve([SpeakerCluster(id: "S1", centroid: embedding([0, 1]), duration: 10)])
        let idB = try #require(second["S1"]?.id)
        #expect(idA != idB)
    }

    @Test func contestedIdentityGoesToTheDominantSpeaker() async throws {
        let store = SpeakerStore(directory: directory)
        let enrolled = await store.resolve([SpeakerCluster(id: "S1", centroid: embedding([1]), duration: 20)])
        let idA = try #require(enrolled["S1"]?.id)

        // Two clusters resemble the enrolled voice in one session; only the longer-speaking one
        // claims the identity, the other enrolls fresh.
        let next = SpeakerStore(directory: directory)
        let resolved = await next.resolve([
            SpeakerCluster(id: "long", centroid: embedding([1, 0.01]), duration: 30),
            SpeakerCluster(id: "short", centroid: embedding([1, 0.02]), duration: 5),
        ])
        #expect(resolved["long"]?.id == idA)
        #expect(resolved["short"]?.id != idA)
    }

    @Test func shortUnmatchedSpeakerStaysPositional() async {
        let store = SpeakerStore(directory: directory)
        // Below the 1.0s enroll floor and matching nothing: no identity, no enrollment.
        let resolved = await store.resolve([SpeakerCluster(id: "S1", centroid: embedding([1]), duration: 0.5)])
        #expect(resolved["S1"] == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("voiceprints.json").path))
    }

    @Test func shortSpeakerStillMatchesExisting() async throws {
        let first = SpeakerStore(directory: directory)
        let enrolled = await first.resolve([SpeakerCluster(id: "S1", centroid: embedding([1]), duration: 12)])
        let id = try #require(enrolled["S1"]?.id)

        // A brief utterance from a known voice still resolves, even under the enroll floor.
        let second = SpeakerStore(directory: directory)
        let matched = await second.resolve([SpeakerCluster(id: "S1", centroid: embedding([1, 0.02]), duration: 0.4)])
        #expect(matched["S1"]?.id == id)
    }

    @Test func persistsEnrolledVoiceprints() async throws {
        let store = SpeakerStore(directory: directory)
        _ = await store.resolve([SpeakerCluster(id: "S1", centroid: embedding([1]), duration: 10)])

        let url = directory.appendingPathComponent("voiceprints.json")
        let voiceprints = try JSONDecoder().decode([Voiceprint].self, from: Data(contentsOf: url))
        #expect(voiceprints.count == 1)
        #expect(voiceprints.first?.embedding.count == SpeakerManager.embeddingSize)
        #expect(voiceprints.first?.name == nil)
    }
}
