import Foundation
@testable import hark
import Testing

/// Covers the `Voiceprint` sample schema: the duration-weighted centroid, the sample cap and its
/// eviction order, and backward-compatible decoding of legacy single-centroid rows.
struct VoiceprintTests {
    private func sample(
        _ embedding: [Float], duration: Float, at enrolledAt: Date = .distantPast, id: UUID = UUID()
    ) -> VoiceSample {
        VoiceSample(id: id, embedding: embedding, duration: duration, enrolledAt: enrolledAt)
    }

    @Test func singleSampleCentroidIsTheEmbeddingItself() {
        let voiceprint = Voiceprint(id: "a", name: nil, samples: [sample([0.1, 0.2, 0.3], duration: 4)])
        #expect(voiceprint.centroid == [0.1, 0.2, 0.3])
        #expect(voiceprint.totalDuration == 4)
    }

    @Test func centroidIsTheDurationWeightedMean() {
        let voiceprint = Voiceprint(id: "a", name: nil, samples: [
            sample([2, 0], duration: 1),
            sample([0, 4], duration: 3),
        ])
        // ([2·1 + 0·3] / 4, [0·1 + 4·3] / 4) = (0.5, 3.0).
        #expect(voiceprint.centroid == [0.5, 3.0])
        #expect(voiceprint.totalDuration == 4)
    }

    @Test func samplesAreCappedDroppingOldest() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let samples = (0 ..< Voiceprint.maxSamples + 2).map { index in
            sample([Float(index)], duration: 1, at: base.addingTimeInterval(Double(index)))
        }
        let voiceprint = Voiceprint(id: "a", name: nil, samples: samples)
        #expect(voiceprint.samples.count == Voiceprint.maxSamples)
        // The two oldest (0 and 1) are evicted; the newest survive in enrollment order.
        #expect(voiceprint.samples.map(\.embedding) == [[2], [3], [4], [5], [6]])
    }

    @Test func legacyRowDecodesToOneSample() throws {
        let json = Data("""
        [{"id": "abc", "name": null, "embedding": [1, 2, 3], "duration": 4}]
        """.utf8)
        let voiceprints = try JSONDecoder().decode([Voiceprint].self, from: json)
        let voiceprint = try #require(voiceprints.first)
        #expect(voiceprint.id == "abc")
        #expect(voiceprint.name == nil)
        // The decoded sample carries a freshly minted id, so compare the carried fields, not equality.
        let onlySample = try #require(voiceprint.samples.first)
        #expect(voiceprint.samples.count == 1)
        #expect(onlySample.embedding == [1, 2, 3])
        #expect(onlySample.duration == 4)
        #expect(onlySample.enrolledAt == .distantPast)
    }

    @Test func writeJSONRoundTripsTheSampleSchema() throws {
        let voiceprint = Voiceprint(id: "abc", name: "Ada", samples: [
            sample([1, 2], duration: 2, at: Date(timeIntervalSinceReferenceDate: 100)),
            sample([3, 4], duration: 6, at: Date(timeIntervalSinceReferenceDate: 200)),
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hark-voiceprint-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try [voiceprint].writeJSON(to: url)
        let decoded = try JSONDecoder().decode([Voiceprint].self, from: Data(contentsOf: url))
        #expect(decoded == [voiceprint])
        #expect(decoded.first?.samples.map(\.id) == voiceprint.samples.map(\.id)) // ids survive the round-trip
    }

    @Test func sampleWithoutIDDecodesToAFreshID() throws {
        // Samples persisted before `id` existed lack the field; decode backfills one rather than throwing.
        let json = Data("""
        [{"embedding": [1, 2], "duration": 3, "enrolledAt": 0}]
        """.utf8)
        let decoded = try JSONDecoder().decode([VoiceSample].self, from: json)
        let sample = try #require(decoded.first)
        #expect(sample.embedding == [1, 2])
        #expect(sample.duration == 3)
        // A second decode mints a different id, proving the backfill is fresh rather than a fixed sentinel.
        let again = try JSONDecoder().decode([VoiceSample].self, from: json)
        #expect(again.first?.id != sample.id)
    }
}
