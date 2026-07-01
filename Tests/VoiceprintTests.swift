import Foundation
@testable import hark
import Testing

/// Covers the `Voiceprint` sample schema: the duration-weighted centroid, the sample cap and its
/// eviction order, and the JSON round-trip.
struct VoiceprintTests {
    private func sample(_ embedding: [Float], duration: Float, at enrolledAt: Date = .distantPast) -> VoiceSample {
        VoiceSample(id: UUID(), embedding: embedding, duration: duration, enrolledAt: enrolledAt)
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
}
