import Foundation

/// One enrollment sample for a voiceprint, a diarized mean embedding with its speech duration and
/// capture time. `id` addresses the sample stably across sessions.
struct VoiceSample: Codable, Equatable, Identifiable {
    let id: UUID
    let embedding: [Float]
    let duration: Float
    let enrolledAt: Date
}

/// A speaker's cross-session identity, backed by a capped list of enrollment samples. The vector
/// matched against is the samples' duration-weighted `centroid`, derived when seeding the matcher
/// rather than stored. Persisted as `{id, name, samples}`.
struct Voiceprint: Codable, Equatable {
    let id: String
    let name: String?
    let samples: [VoiceSample]
    /// When set, this voiceprint was merged into another; lookups follow the redirect to the survivor
    /// so other sessions still bound to this id resolve instead of falling back to positional.
    let redirectID: String?

    /// Cap on samples per voiceprint, from `Preferences`. The initializer keeps the newest this many.
    static var maxSamples: Int {
        Preferences.voiceprintMaxSamples
    }

    init(id: String, name: String?, samples: [VoiceSample], redirectID: String? = nil) {
        self.id = id
        self.name = name
        self.samples = Self.capped(samples)
        self.redirectID = redirectID
    }

    /// The samples' duration-weighted mean embedding, the vector matched against. A single-sample
    /// print returns that embedding unchanged.
    var centroid: [Float] {
        guard let first = samples.first else { return [] }
        guard samples.count > 1 else { return first.embedding }
        var weighted = [Float](repeating: 0, count: first.embedding.count)
        var weight: Float = 0
        for sample in samples where sample.embedding.count == weighted.count {
            weight += sample.duration
            for index in weighted.indices {
                weighted[index] += sample.embedding[index] * sample.duration
            }
        }
        guard weight > 0 else { return first.embedding }
        for index in weighted.indices {
            weighted[index] /= weight
        }
        return weighted
    }

    /// Total enrolled speech across the samples, seeded into the matcher as the speaker's duration.
    var totalDuration: Float {
        samples.reduce(0) { $0 + $1.duration }
    }

    /// When the newest sample was enrolled, the closest thing to "last heard" for the naming UI.
    var lastEnrolledAt: Date? {
        samples.map(\.enrolledAt).max()
    }

    /// The newest `maxSamples` by enrollment time, dropping the oldest (a no-op at or under the cap).
    private static func capped(_ samples: [VoiceSample]) -> [VoiceSample] {
        guard samples.count > maxSamples else { return samples }
        return Array(samples.sorted { $0.enrolledAt < $1.enrolledAt }.suffix(maxSamples))
    }
}

extension Voiceprint: Identifiable {}

extension Voiceprint {
    /// Follows `redirectID` chains to the surviving voiceprint after merges, or `nil` when the id is
    /// unknown or the chain breaks. Guards against cycles.
    static func survivor(of id: String, in voiceprints: [String: Voiceprint]) -> Voiceprint? {
        var current = id
        var seen: Set<String> = []
        while seen.insert(current).inserted, let voiceprint = voiceprints[current] {
            guard let redirect = voiceprint.redirectID else { return voiceprint }
            current = redirect
        }
        return nil
    }
}
