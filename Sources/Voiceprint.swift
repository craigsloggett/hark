import Foundation

/// One enrollment sample for a voiceprint, a diarized mean embedding with its speech duration and
/// capture time. `id` addresses the sample stably across sessions.
struct VoiceSample: Codable, Equatable, Identifiable {
    let id: UUID
    let embedding: Embedding
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

    /// Whether this voiceprint was merged away and now only redirects to its survivor.
    var isTombstone: Bool {
        redirectID != nil
    }

    /// The samples' duration-weighted mean embedding, the vector matched against; `nil` for a
    /// sampleless (tombstoned) voiceprint. A single-sample print returns that embedding unchanged.
    var centroid: Embedding? {
        guard let first = samples.first else { return nil }
        guard samples.count > 1 else { return first.embedding }
        var weighted = [Float](repeating: 0, count: first.embedding.values.count)
        var weight: Float = 0
        for sample in samples {
            weight += sample.duration
            for index in weighted.indices {
                weighted[index] += sample.embedding.values[index] * sample.duration
            }
        }
        guard weight > 0 else { return first.embedding }
        for index in weighted.indices {
            weighted[index] /= weight
        }
        return Embedding(weighted)
    }

    /// Total enrolled speech across the samples, seeded into the matcher as the speaker's duration.
    var totalDuration: Float {
        samples.reduce(0) { $0 + $1.duration }
    }

    /// The newest `maxSamples` by enrollment time, dropping the oldest (a no-op at or under the cap).
    private static func capped(_ samples: [VoiceSample]) -> [VoiceSample] {
        guard samples.count > maxSamples else { return samples }
        return Array(samples.sorted { $0.enrolledAt < $1.enrolledAt }.suffix(maxSamples))
    }
}

extension Voiceprint: Identifiable {}

extension [Voiceprint] {
    /// The voiceprints keyed by id. Ids are unique by construction; the uniquing is defensive.
    var byID: [String: Voiceprint] {
        Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Copy helpers for the store's edits, so every construction flows through the capping initializer.
extension Voiceprint {
    /// A copy with `name` replacing the current one (`nil` clears it back to unnamed).
    func renamed(to name: String?) -> Voiceprint {
        Voiceprint(id: id, name: name, samples: samples, redirectID: redirectID)
    }

    /// A copy with `sample` appended (and the oldest evicted past the cap).
    func adding(_ sample: VoiceSample) -> Voiceprint {
        Voiceprint(id: id, name: name, samples: samples + [sample], redirectID: redirectID)
    }

    /// The tombstone this voiceprint leaves behind when merged into `survivorID`.
    func redirected(to survivorID: String) -> Voiceprint {
        Voiceprint(id: id, name: nil, samples: [], redirectID: survivorID)
    }
}

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
