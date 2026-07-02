import Foundation
@testable import hark
import Testing

/// Exercises `SpeakerStore`'s matching with synthetic 256-d embeddings, so no model download is
/// needed (matching is pure vector math). Each test gets its own temporary voiceprint directory.
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

    @Test func enrollsThenMatchesAcrossStores() async throws {
        let first = SpeakerStore(directory: directory)
        let enrolled = await first.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 12)])
        let id = try #require(enrolled["S1"]?.id)
        #expect(enrolled["S1"]?.name == nil) // new voiceprints are unnamed

        // A fresh store loads the persisted database and matches the same voice (near, not identical).
        let second = SpeakerStore(directory: directory)
        let matched = await second.resolve([SpeakerCluster(id: "S1", embedding: embedding([1, 0.02]), duration: 8)])
        #expect(matched["S1"]?.id == id)
    }

    @Test func matchCarriesDistanceButEnrollmentDoesNot() async {
        let first = SpeakerStore(directory: directory)
        let enrolled = await first.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 12)])
        #expect(enrolled["S1"]?.distance == nil) // a freshly enrolled voice is new, not matched

        let second = SpeakerStore(directory: directory)
        let matched = await second.resolve([SpeakerCluster(id: "S1", embedding: embedding([1, 0.02]), duration: 8)])
        #expect(matched["S1"]?.distance != nil) // a match records how close it was, for the "Likely" cue
    }

    @Test func unmatchedVoiceEnrollsAsNew() async throws {
        let store = SpeakerStore(directory: directory)
        let first = await store.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 10)])
        let idA = try #require(first["S1"]?.id)

        // An orthogonal embedding is cosine distance 1.0, well past the 0.65 threshold.
        let next = SpeakerStore(directory: directory)
        let second = await next.resolve([SpeakerCluster(id: "S1", embedding: embedding([0, 1]), duration: 10)])
        let idB = try #require(second["S1"]?.id)
        #expect(idA != idB)
    }

    @Test func contestedIdentityGoesToTheDominantSpeaker() async throws {
        let store = SpeakerStore(directory: directory)
        let enrolled = await store.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 20)])
        let idA = try #require(enrolled["S1"]?.id)

        // Two clusters resemble the enrolled voice in one session (only the longer-speaking one
        // claims the identity, the other enrolls fresh).
        let next = SpeakerStore(directory: directory)
        let resolved = await next.resolve([
            SpeakerCluster(id: "long", embedding: embedding([1, 0.01]), duration: 30),
            SpeakerCluster(id: "short", embedding: embedding([1, 0.02]), duration: 5),
        ])
        #expect(resolved["long"]?.id == idA)
        #expect(resolved["short"]?.id != idA)
    }

    @Test func shortUnmatchedSpeakerStaysPositional() async {
        let store = SpeakerStore(directory: directory)
        // Below the 1.0s enroll floor and matching nothing, so no identity and no enrollment.
        let resolved = await store.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 0.5)])
        #expect(resolved["S1"] == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("voiceprints.json").path))
    }

    @Test func shortSpeakerStillMatchesExisting() async throws {
        let first = SpeakerStore(directory: directory)
        let enrolled = await first.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 12)])
        let id = try #require(enrolled["S1"]?.id)

        // A brief utterance from a known voice still resolves, even under the enroll floor.
        let second = SpeakerStore(directory: directory)
        let matched = await second.resolve([SpeakerCluster(id: "S1", embedding: embedding([1, 0.02]), duration: 0.4)])
        #expect(matched["S1"]?.id == id)
    }

    @Test func persistsEnrolledVoiceprints() async throws {
        let store = SpeakerStore(directory: directory)
        _ = await store.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 10)])

        let url = directory.appendingPathComponent("voiceprints.json")
        let voiceprints = try JSONDecoder().decode([Voiceprint].self, from: Data(contentsOf: url))
        #expect(voiceprints.count == 1)
        #expect(voiceprints.first?.samples.count == 1)
        #expect(voiceprints.first?.samples.first?.embedding == embedding([1]))
        #expect(voiceprints.first?.name == nil)
    }

    // MARK: Naming

    @Test func renameSetsThenClearsName() async throws {
        let store = SpeakerStore(directory: directory)
        let enrolled = await store.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 10)])
        let id = try #require(enrolled["S1"]?.id)

        try await store.rename(id: id, to: "Ada")
        let named = try await store.voiceprints()
        #expect(named.first?.name == "Ada")

        // Whitespace-only clears the name back to unnamed.
        try await store.rename(id: id, to: "   ")
        let cleared = try await store.voiceprints()
        #expect(cleared.first?.name == nil)
    }

    @Test func renameIgnoresUnknownID() async throws {
        let store = SpeakerStore(directory: directory)
        _ = await store.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 10)])
        try await store.rename(id: "not-a-real-id", to: "Ghost")
        let voiceprints = try await store.voiceprints()
        #expect(voiceprints.allSatisfy { $0.name == nil })
    }

    @Test func removeForgetsVoiceprint() async throws {
        let store = SpeakerStore(directory: directory)
        let enrolled = await store.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 10)])
        let id = try #require(enrolled["S1"]?.id)

        try await store.remove(id: id)
        let remaining = try await store.voiceprints()
        #expect(remaining.isEmpty)
    }

    @Test func namePersistsForTheNextSession() async throws {
        let first = SpeakerStore(directory: directory)
        let enrolled = await first.resolve([SpeakerCluster(id: "S1", embedding: embedding([1]), duration: 12)])
        let id = try #require(enrolled["S1"]?.id)
        try await first.rename(id: id, to: "Ada")

        // A fresh store matching the same voice carries the name into the resolved identity.
        let second = SpeakerStore(directory: directory)
        let matched = await second.resolve([SpeakerCluster(id: "S1", embedding: embedding([1, 0.02]), duration: 8)])
        #expect(matched["S1"]?.name == "Ada")
    }

    // MARK: Identity operations

    @Test func enrollCreatesANamedVoiceprint() async throws {
        let store = SpeakerStore(directory: directory)
        let voiceprint = try await store.enroll(embedding: embedding([1]), duration: 3, name: "Ada")
        #expect(voiceprint.name == "Ada")
        #expect(voiceprint.samples.count == 1)
        let all = try await store.voiceprints()
        #expect(all.map(\.id) == [voiceprint.id])
    }

    @Test func addSampleGrowsTheVoiceprint() async throws {
        let store = SpeakerStore(directory: directory)
        let voiceprint = try await store.enroll(embedding: embedding([1]), duration: 3, name: nil)
        try await store.addSample(toVoiceprint: voiceprint.id, embedding: embedding([1, 0.1]), duration: 2)
        let reloaded = try await store.voiceprints().first { $0.id == voiceprint.id }
        #expect(reloaded?.samples.count == 2)
    }

    @Test func mergeCombinesSamplesAndRedirectsSource() async throws {
        let store = SpeakerStore(directory: directory)
        let ada = try await store.enroll(embedding: embedding([1]), duration: 3, name: "Ada")
        let other = try await store.enroll(embedding: embedding([0, 1]), duration: 4, name: nil)

        let merged = try await store.merge(other.id, into: ada.id)
        #expect(merged.id == ada.id)
        #expect(merged.name == "Ada")
        #expect(merged.samples.count == 2)
        // The source is tombstoned; `voiceprint(id:)` follows the redirect to the survivor.
        let followed = try await store.voiceprint(id: other.id)
        #expect(followed?.id == ada.id)
    }

    @Test func renameFollowsMergeRedirect() async throws {
        let store = SpeakerStore(directory: directory)
        let ada = try await store.enroll(embedding: embedding([1]), duration: 3, name: "Ada")
        let duplicate = try await store.enroll(embedding: embedding([1, 0.01]), duration: 2, name: nil)
        _ = try await store.merge(duplicate.id, into: ada.id)

        // A session merged elsewhere can still hold the tombstoned id; renaming through it renames
        // the survivor rather than silently naming the tombstone.
        try await store.rename(id: duplicate.id, to: "Ada Lovelace")
        let survivor = try await store.voiceprint(id: ada.id)
        #expect(survivor?.name == "Ada Lovelace")
    }

    @Test func addSampleFollowsMergeRedirect() async throws {
        let store = SpeakerStore(directory: directory)
        let ada = try await store.enroll(embedding: embedding([1]), duration: 3, name: "Ada")
        let duplicate = try await store.enroll(embedding: embedding([1, 0.01]), duration: 2, name: nil)
        _ = try await store.merge(duplicate.id, into: ada.id)

        // Teaching through the tombstoned id grows the survivor. The tombstone must stay sampleless,
        // or it would regain a centroid and future sessions could match a merged-away id.
        try await store.addSample(toVoiceprint: duplicate.id, embedding: embedding([1, 0.02]), duration: 2)
        let all = try await store.voiceprints()
        #expect(all.first { $0.id == ada.id }?.samples.count == 3)
        #expect(all.first { $0.id == duplicate.id }?.samples.isEmpty == true)
    }

    @Test func removeFollowsMergeRedirect() async throws {
        let store = SpeakerStore(directory: directory)
        let ada = try await store.enroll(embedding: embedding([1]), duration: 3, name: "Ada")
        let duplicate = try await store.enroll(embedding: embedding([1, 0.01]), duration: 2, name: nil)
        _ = try await store.merge(duplicate.id, into: ada.id)

        // Forgetting through the tombstoned id forgets the surviving voice.
        try await store.remove(id: duplicate.id)
        let remaining = try await store.voiceprints()
        #expect(!remaining.contains { $0.id == ada.id })
    }

    @Test func nearestNamedFindsTheClosestSavedVoice() async throws {
        let store = SpeakerStore(directory: directory)
        let ada = try await store.enroll(embedding: embedding([1]), duration: 3, name: "Ada")
        _ = try await store.enroll(embedding: embedding([0, 1]), duration: 3, name: "Bo")

        // An embedding near Ada resolves to Ada with a small distance, the duplicate-guard signal.
        let near = try await store.nearestNamed(to: embedding([1, 0.02]))
        #expect(near?.voiceprint.id == ada.id)
        #expect((near?.distance ?? 1) < 0.1)
    }

    @Test func nearestNamedIgnoresUnnamedVoices() async throws {
        let store = SpeakerStore(directory: directory)
        _ = try await store.enroll(embedding: embedding([1]), duration: 3, name: nil)
        // No named voice to match, so an unnamed near-identical print is not offered as a duplicate.
        let near = try await store.nearestNamed(to: embedding([1, 0.02]))
        #expect(near == nil)
    }

    @Test func duplicatePairsSurfaceNearIdenticalVoices() async throws {
        let store = SpeakerStore(directory: directory)
        let ada = try await store.enroll(embedding: embedding([1]), duration: 3, name: "Ada")
        let adaAgain = try await store.enroll(embedding: embedding([1, 0.01]), duration: 3, name: nil)
        _ = try await store.enroll(embedding: embedding([0, 1]), duration: 3, name: "Bo") // orthogonal, far

        // Only the two near-identical prints pair up; the orthogonal voice is well past the window.
        let pairs = try await store.duplicatePairs(within: 0.4)
        let pair = try #require(pairs.first)
        #expect(pairs.count == 1)
        #expect(Set([pair.first.id, pair.second.id]) == Set([ada.id, adaAgain.id]))
    }

    @Test func replaceAllRestoresAnEarlierSnapshot() async throws {
        let store = SpeakerStore(directory: directory)
        let ada = try await store.enroll(embedding: embedding([1]), duration: 3, name: "Ada")
        let other = try await store.enroll(embedding: embedding([0, 1]), duration: 4, name: nil)
        let snapshot = try await store.voiceprints() // Ada and the unnamed voice, both intact.

        // Merge tombstones the source; restoring the snapshot rolls the whole database back, the undo
        // primitive the labeling window relies on.
        _ = try await store.merge(other.id, into: ada.id)
        try await store.replaceAll(snapshot)

        let restored = try await store.voiceprints()
        #expect(Set(restored.map(\.id)) == Set([ada.id, other.id]))
        #expect(restored.first { $0.id == other.id }?.redirectID == nil)
        #expect(restored.first { $0.id == ada.id }?.samples.count == 1)
    }
}
