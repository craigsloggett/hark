import FluidAudio
import Foundation
import OSLog

/// One session's diarized speaker, holding the diarizer's cluster id, its mean embedding, and speech duration.
struct SpeakerCluster {
    let id: String
    let embedding: [Float]
    let duration: Float
}

/// One enrollment sample for a voiceprint: a diarized mean embedding, its speech duration (the
/// centroid's weight), and when it was captured (the cap's eviction key).
struct VoiceSample: Codable, Equatable {
    let embedding: [Float]
    let duration: Float
    let enrolledAt: Date
}

/// A speaker's cross-session identity, backed by a capped list of enrollment samples. The vector
/// matched against is the samples' duration-weighted `centroid`, derived when seeding the matcher
/// rather than stored, so adaptation can append samples later without a schema migration. Persisted
/// as `{id, name, samples}`; a legacy `{id, name, embedding, duration}` row decodes to one sample.
struct Voiceprint: Codable, Equatable {
    let id: String
    let name: String?
    let samples: [VoiceSample]

    /// Newest samples kept per voiceprint; enrolling past this evicts the oldest, bounding the database.
    static let maxSamples = 5

    init(id: String, name: String?, samples: [VoiceSample]) {
        self.id = id
        self.name = name
        self.samples = Self.capped(samples)
    }

    /// The samples' duration-weighted mean embedding, the vector matched against. A single-sample
    /// print returns that embedding unchanged, so enrollment matches identically to a stored centroid.
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

    /// The newest `maxSamples` by enrollment time, dropping the oldest; a no-op at or under the cap.
    private static func capped(_ samples: [VoiceSample]) -> [VoiceSample] {
        guard samples.count > maxSamples else { return samples }
        return Array(samples.sorted { $0.enrolledAt < $1.enrolledAt }.suffix(maxSamples))
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, samples
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case embedding, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        if let samples = try container.decodeIfPresent([VoiceSample].self, forKey: .samples) {
            self.init(id: id, name: name, samples: samples)
        } else {
            // Pre-samples row: fold the single {embedding, duration} centroid into one sample. The
            // distant-past date sorts it oldest, so it is first to evict once adaptation appends.
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let embedding = try legacy.decode([Float].self, forKey: .embedding)
            let duration = try legacy.decode(Float.self, forKey: .duration)
            self.init(
                id: id, name: name,
                samples: [VoiceSample(embedding: embedding, duration: duration, enrolledAt: .distantPast)]
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(samples, forKey: .samples)
    }
}

/// A session speaker's resolved identity (`name` is `nil` until the voiceprint is named).
struct SpeakerIdentity: Codable, Equatable {
    let id: String
    let name: String?
}

/// Matches each session's diarized speakers against a persisted voiceprint database so a recurring
/// voice keeps a stable identity across sessions. Matching is read-only against a pre-session
/// snapshot, so two voices in one meeting can't collapse together (unmatched speakers enroll only
/// past a duration floor, keeping brief diarization fragments out of the database).
actor SpeakerStore {
    private let directory: URL?
    private let logger = Logger(category: "SpeakerStore")

    /// - Parameter directory: where `voiceprints.json` lives (defaults to the sandbox container's
    ///   `Application Support/Hark`).
    init(directory: URL? = nil) {
        self.directory = directory
    }

    /// Resolves each cluster to a stable identity, enrolling and persisting new voiceprints.
    /// - Returns: cluster id to identity (empty when the database can't be read, so a corrupt file
    ///   degrades to positional speakers instead of being overwritten).
    func resolve(_ clusters: [SpeakerCluster]) -> [String: SpeakerIdentity] {
        let known: [Voiceprint]
        do {
            known = try load()
        } catch {
            logger.error("Couldn't read voiceprints, leaving speakers positional: \(error, privacy: .public)")
            return [:]
        }

        let threshold = Float(Preferences.speakerMatchThreshold)
        let enrollFloor = Float(Preferences.speakerMinEnrollmentDuration)
        let snapshot = matcher(seededWith: known, threshold: threshold)

        let (resolved, enrolled) = assign(
            clusters, against: snapshot, known: known, threshold: threshold, enrollFloor: enrollFloor
        )
        writeDebugDump(clusters, against: snapshot, threshold: threshold)

        let summary = String(format: "Resolved %d/%d speakers, %d new", resolved.count, clusters.count, enrolled.count)
        logger.log("\(summary, privacy: .public)")

        if !enrolled.isEmpty {
            do {
                try save(known + enrolled)
            } catch {
                logger.error("Couldn't persist voiceprints: \(error, privacy: .public)")
            }
        }
        return resolved
    }

    /// Matches each cluster against the frozen snapshot and decides enrollments, without persisting.
    private func assign(
        _ clusters: [SpeakerCluster],
        against snapshot: SpeakerManager,
        known: [Voiceprint],
        threshold: Float,
        enrollFloor: Float
    ) -> (resolved: [String: SpeakerIdentity], enrolled: [Voiceprint]) {
        var byID: [String: Voiceprint] = [:]
        for voiceprint in known {
            byID[voiceprint.id] = voiceprint
        }

        var claimed: Set<String> = []
        var enrolled: [Voiceprint] = []
        var resolved: [String: SpeakerIdentity] = [:]

        // Longest-speaking cluster claims a contested identity first (later claimants enroll fresh).
        for cluster in clusters.sorted(by: { $0.duration > $1.duration }) {
            guard cluster.embedding.count == SpeakerManager.embeddingSize else { continue }
            let matches = snapshot.findMatchingSpeakers(with: cluster.embedding, speakerThreshold: threshold)
            // matches is nearest-first so the first unclaimed match is the closest identity still
            // available to this cluster.
            if let match = matches.first(where: { !claimed.contains($0.id) }) {
                claimed.insert(match.id)
                resolved[cluster.id] = SpeakerIdentity(id: match.id, name: byID[match.id]?.name)
            } else if cluster.duration >= enrollFloor {
                let sample = VoiceSample(
                    embedding: cluster.embedding, duration: cluster.duration, enrolledAt: Date()
                )
                let fresh = Voiceprint(id: UUID().uuidString, name: nil, samples: [sample])
                enrolled.append(fresh)
                claimed.insert(fresh.id)
                resolved[cluster.id] = SpeakerIdentity(id: fresh.id, name: nil)
            }
        }
        return (resolved, enrolled)
    }

    /// A `SpeakerManager` seeded with the known voiceprints for read-only matching. Built via
    /// `upsertSpeaker` to avoid naming FluidAudio's `Speaker`, which a same-named module type shadows.
    private func matcher(seededWith known: [Voiceprint], threshold: Float) -> SpeakerManager {
        var manager = SpeakerManager(speakerThreshold: threshold)
        for voiceprint in known {
            let centroid = voiceprint.centroid
            guard centroid.count == SpeakerManager.embeddingSize else { continue }
            manager.upsertSpeaker(
                id: voiceprint.id, currentEmbedding: centroid, duration: voiceprint.totalDuration
            )
        }
        return manager
    }

    // MARK: Persistence

    private func load() throws -> [Voiceprint] {
        let url = try voiceprintsURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Voiceprint].self, from: Data(contentsOf: url))
    }

    private func save(_ voiceprints: [Voiceprint]) throws {
        try voiceprints.writeJSON(to: voiceprintsURL())
    }

    private func voiceprintsURL() throws -> URL {
        let folder: URL = if let directory {
            directory
        } else {
            try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Hark", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("voiceprints.json")
    }

    // MARK: Debug

    /// When `HARK_SPEAKER_DEBUG` is set, writes each cluster's nearest known voiceprint and distance
    /// to `matches.debug.json` beside the database, for tuning `speakerMatchThreshold`.
    private func writeDebugDump(_ clusters: [SpeakerCluster], against snapshot: SpeakerManager, threshold: Float) {
        guard ProcessInfo.processInfo.flag(forKey: "HARK_SPEAKER_DEBUG") else { return }
        let dump = clusters
            .filter { $0.embedding.count == SpeakerManager.embeddingSize }
            .map { cluster -> DebugMatch in
                // 2 is the maximum cosine distance, so this ranks every known voiceprint (.first is nearest).
                let nearest = snapshot.findMatchingSpeakers(with: cluster.embedding, speakerThreshold: 2).first
                return DebugMatch(
                    cluster: cluster.id,
                    duration: Double(cluster.duration),
                    nearest: nearest?.id,
                    distance: nearest.map { Double($0.distance) },
                    threshold: Double(threshold)
                )
            }
        do {
            let folder = try voiceprintsURL().deletingLastPathComponent()
            try dump.writeJSON(to: folder.appendingPathComponent("matches.debug.json"), sortedKeys: true)
        } catch {
            logger.error("Couldn't write speaker debug dump: \(error, privacy: .public)")
        }
    }

    /// One cluster's match outcome in the `HARK_SPEAKER_DEBUG` dump.
    private struct DebugMatch: Encodable {
        let cluster: String
        let duration: Double
        let nearest: String?
        let distance: Double?
        let matched: Bool

        init(cluster: String, duration: Double, nearest: String?, distance: Double?, threshold: Double) {
            self.cluster = cluster
            self.duration = duration
            self.nearest = nearest
            self.distance = distance
            matched = distance.map { $0 <= threshold } ?? false
        }
    }
}
